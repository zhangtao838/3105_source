import Foundation
import AVFoundation
import UIKit
import UniformTypeIdentifiers

enum WallpaperVideoError: Error, LocalizedError {
    case unsupportedVideo
    case decodeFailed
    case exportFailed
    case thumbnailFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedVideo: return "Unsupported video format"
        case .decodeFailed: return "Failed to decode video"
        case .exportFailed: return "Failed to export video"
        case .thumbnailFailed: return "Failed to generate thumbnail"
        }
    }
}

struct WallpaperVideoConversionOptions {
    var trimStart: CMTime = .zero
    var trimDuration: CMTime = CMTime(seconds: 10, preferredTimescale: 600)
    var targetBitrate: Int = 2_000_000
    var loop: Bool = true
}

enum WallpaperVideoConverter {

    static let maxVideoBytes: Int64 = 80 * 1_024 * 1_024

    static func convert(
        videoURL: URL,
        options: WallpaperVideoConversionOptions = .init(),
        outputDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        let didAccess = videoURL.startAccessingSecurityScopedResource()
        defer { if didAccess { videoURL.stopAccessingSecurityScopedResource() } }

        let asset = AVURLAsset(url: videoURL)
        guard let videoTrack = asset.tracks(withMediaType: .video).first else {
            throw WallpaperVideoError.unsupportedVideo
        }

        let descriptorID = UUID().uuidString.uppercased()
        let packageRoot = outputDirectory.appendingPathComponent("pkg-\(descriptorID)", isDirectory: true)
        let descriptorURL = packageRoot.appendingPathComponent("descriptors/\(descriptorID)", isDirectory: true)
        let contentsURL = descriptorURL.appendingPathComponent("versions/1/contents/video.wallpaper", isDirectory: true)
        try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let videoOutputURL = contentsURL.appendingPathComponent("video.mp4")
        let posterOutputURL = contentsURL.appendingPathComponent("poster.heic")

        try exportVideo(
            asset: asset,
            videoTrack: videoTrack,
            options: options,
            outputURL: videoOutputURL
        )

        try generatePoster(
            asset: asset,
            time: options.trimStart,
            outputURL: posterOutputURL
        )

        let identifier = Int.random(in: 10_000...2_000_000_000)

        try writeDescriptorFiles(at: descriptorURL, identifier: identifier)
        try writeWallpaperMetadata(at: contentsURL, identifier: identifier, duration: options.trimDuration.seconds)

        let tendiesURL = outputDirectory.appendingPathComponent(
            "video-\(descriptorID).tendies"
        )
        try packageAsTendies(
            descriptorRoot: packageRoot,
            outputURL: tendiesURL,
            fileManager: fileManager
        )

        return tendiesURL
    }

    private static func writeDescriptorFiles(at descriptorURL: URL, identifier: Int) throws {
        let identifierData = String(identifier).data(using: .utf8)
        try identifierData?.write(
            to: descriptorURL.appendingPathComponent("com.apple.posterkit.provider.descriptor.identifier"),
            options: .atomic
        )

        let roleData = "PRPosterRoleLockScreen".data(using: .utf8)
        try roleData?.write(
            to: descriptorURL.appendingPathComponent("com.apple.posterkit.role.identifier"),
            options: .atomic
        )

        let providerInfo: [String: Any] = [
            "providerIdentifier": "com.apple.PhotosUIPrivate.PhotosPosterProvider",
            "descriptorIdentifier": identifier
        ]
        let providerData = try PropertyListSerialization.data(
            fromPropertyList: providerInfo,
            format: .binary,
            options: 0
        )
        try providerData.write(
            to: descriptorURL.appendingPathComponent("providerInfo.plist"),
            options: .atomic
        )
    }

    private static func writeWallpaperMetadata(at contentsURL: URL, identifier: Int, duration: Double) throws {
        let metadata: [String: Any] = [
            "identifier": identifier,
            "video": "video.mp4",
            "poster": "poster.heic",
            "duration": duration,
            "autoplay": true,
            "muted": true,
            "type": "video"
        ]
        let data = try PropertyListSerialization.data(
            fromPropertyList: metadata,
            format: .binary,
            options: 0
        )
        try data.write(
            to: contentsURL.appendingPathComponent("Wallpaper.plist"),
            options: .atomic
        )
    }

    private static func exportVideo(
        asset: AVAsset,
        videoTrack: AVAssetTrack,
        options: WallpaperVideoConversionOptions,
        outputURL: URL
    ) throws {
        guard let export = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw WallpaperVideoError.exportFailed
        }

        export.outputURL = outputURL
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true

        let startTime = options.trimStart
        let endTime = CMTimeAdd(startTime, options.trimDuration)
        export.timeRange = CMTimeRange(start: startTime, end: endTime)

        let semaphore = DispatchSemaphore(value: 0)
        var exportError: Error?

        export.exportAsynchronously {
            if export.status == .failed {
                exportError = export.error
            }
            semaphore.signal()
        }
        semaphore.wait()

        if let exportError {
            throw exportError
        }
        guard export.status == .completed else {
            throw WallpaperVideoError.exportFailed
        }
    }

    private static func generatePoster(
        asset: AVAsset,
        time: CMTime,
        outputURL: URL
    ) throws {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1080, height: 1920)

        do {
            let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
            let image = UIImage(cgImage: cgImage)
            guard let data = image.heicData() else {
                throw WallpaperVideoError.thumbnailFailed
            }
            try data.write(to: outputURL, options: .atomic)
        } catch {
            throw WallpaperVideoError.thumbnailFailed
        }
    }

    private static func packageAsTendies(
        descriptorRoot: URL,
        outputURL: URL,
        fileManager: FileManager
    ) throws {
        let coordinator = NSFileCoordinator()
        var error: NSError?
        coordinator.coordinate(
            readingItemAt: descriptorRoot,
            options: .forUploading,
            error: &error
        ) { zipURL in
            try? fileManager.removeItem(at: outputURL)
            try? fileManager.copyItem(at: zipURL, to: outputURL)
        }
        if let error {
            throw error
        }
        guard fileManager.fileExists(atPath: outputURL.path) else {
            throw WallpaperVideoError.exportFailed
        }
    }
}

extension UIImage {
    func heicData(compressionQuality: CGFloat = 0.85) -> Data? {
        guard let cgImage = cgImage,
              let mutableData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(
                  mutableData,
                  "public.heic" as CFString,
                  1,
                  nil
              ) else { return nil }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: compressionQuality
        ]
        CGImageDestinationAddImage(destination, cgImage, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return mutableData as Data
    }
}

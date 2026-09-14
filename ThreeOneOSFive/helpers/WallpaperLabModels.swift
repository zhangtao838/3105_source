import Foundation

enum WallpaperLabError: Error, Equatable {
    case unsafeContainerRoot
    case posterStoreUnavailable
    case unsupportedPosterLayout
    case unsupportedPackage
    case unsafeArchive
    case symbolicLinkUnsupported
    case packageTooLarge
    case noDescriptors
    case accessDenied
    case backupFailed
    case installFailed
    case restoreFailed
}

extension WallpaperLabError: LocalizedError {
    var localizationKey: String {
        switch self {
        case .unsafeContainerRoot: return "wallpaper.error.unsafe_container"
        case .posterStoreUnavailable: return "wallpaper.error.store_unavailable"
        case .unsupportedPosterLayout: return "wallpaper.error.layout"
        case .unsupportedPackage: return "wallpaper.error.package"
        case .unsafeArchive: return "wallpaper.error.archive"
        case .symbolicLinkUnsupported: return "wallpaper.error.symlink"
        case .packageTooLarge: return "wallpaper.error.size"
        case .noDescriptors: return "wallpaper.error.no_descriptors"
        case .accessDenied: return "wallpaper.error.access"
        case .backupFailed: return "wallpaper.error.backup"
        case .installFailed: return "wallpaper.error.install"
        case .restoreFailed: return "wallpaper.error.restore"
        }
    }

    var errorDescription: String? {
        String(localized: String.LocalizationValue(localizationKey))
    }
}

enum WallpaperLabLimits {
    static let maximumArchiveBytes: Int64 = 2 * 1_024 * 1_024 * 1_024
    static let maximumExpandedBytes: Int64 = 3 * 1_024 * 1_024 * 1_024
    static let maximumEntryBytes: Int64 = 1 * 1_024 * 1_024 * 1_024
    static let maximumEntryCount = 50_000
    static let maximumDescriptorCount = 256
    static let maximumPathBytes = 8_192
}

enum WallpaperPosterType: String, CaseIterable {
    case collections = "Collections"
    case photos = "Photos"
    case mercury = "Mercury"
    case weather = "Weather"
    case astronomy = "Astronomy"
    case pride = "Pride"
    case unity = "Unity"
    case emoji = "Emoji"
    case color = "Color"
    case gradient = "Gradient"
    case kaleidoscope = "Kaleidoscope"
    case custom = "Custom"

    var displayName: String { rawValue }
    var systemImage: String {
        switch self {
        case .collections: return "square.stack.3d.down.right"
        case .photos: return "video.fill"
        case .mercury: return "circle.hexagongrid.fill"
        case .weather: return "cloud.sun.fill"
        case .astronomy: return "moon.stars.fill"
        case .pride: return "rainbow"
        case .unity: return "person.3.fill"
        case .emoji: return "face.smiling.fill"
        case .color: return "paintpalette.fill"
        case .gradient: return "circle.righthalf.filled"
        case .kaleidoscope: return "camera.filters"
        case .custom: return "puzzlepiece.extension.fill"
        }
    }
}

struct WallpaperPosterLayout: Equatable {
    static let collectionsExtension = "com.apple.WallpaperKit.CollectionsPoster"
    static let photosExtension = "com.apple.PhotosUIPrivate.PhotosPosterProvider"
    static let mercuryExtension = "com.apple.MercuryPoster"
    static let weatherExtension = "com.apple.WeatherPoster"
    static let astronomyExtension = "com.apple.AstronomyPoster"
    static let prideExtension = "com.apple.PridePoster"
    static let unityExtension = "com.apple.UnityPoster"
    static let emojiExtension = "com.apple.EmojiPoster"
    static let colorExtension = "com.apple.ColorPoster"
    static let gradientExtension = "com.apple.GradientPoster"
    static let kaleidoscopeExtension = "com.apple.KaleidoscopePoster"

    static let allKnownExtensions: [String] = [
        collectionsExtension, photosExtension, mercuryExtension,
        weatherExtension, astronomyExtension, prideExtension,
        unityExtension, emojiExtension, colorExtension,
        gradientExtension, kaleidoscopeExtension
    ]

    let generation: String
    let storeURL: URL
    let extensionDescriptorDirectories: [String: URL]

    var supportsCollections: Bool {
        extensionDescriptorDirectories[Self.collectionsExtension] != nil
    }

    var supportsVideo: Bool {
        extensionDescriptorDirectories[Self.photosExtension] != nil
    }

    var supportedTypes: [WallpaperPosterType] {
        extensionDescriptorDirectories.keys.compactMap { type(for: $0) }
    }

    static func type(for identifier: String) -> WallpaperPosterType? {
        switch identifier {
        case collectionsExtension: return .collections
        case photosExtension: return .photos
        case mercuryExtension: return .mercury
        case weatherExtension: return .weather
        case astronomyExtension: return .astronomy
        case prideExtension: return .pride
        case unityExtension: return .unity
        case emojiExtension: return .emoji
        case colorExtension: return .color
        case gradientExtension: return .gradient
        case kaleidoscopeExtension: return .kaleidoscope
        default:
            return identifier.hasPrefix("com.apple.") ? .custom : nil
        }
    }
}

struct WallpaperDescriptorSource: Equatable, Identifiable {
    let extensionIdentifier: String
    let directoryURL: URL
    let byteCount: Int64
    let fileCount: Int
    let isOrdered: Bool

    var id: String { "\(extensionIdentifier):\(directoryURL.path)" }
}

struct TendiesPayload: Equatable {
    let descriptors: [WallpaperDescriptorSource]
    let totalBytes: Int64
    let fileCount: Int
}

enum WallpaperLayoutScanner {
    static let storeRelativePath = "Library/Application Support/PRBPosterExtensionDataStore"

    typealias RootValidator = (URL) -> Bool

    static func scan(
        containerURL rawContainerURL: URL,
        rootValidator: RootValidator,
        fileManager: FileManager = .default
    ) throws -> WallpaperPosterLayout {
        let containerURL = rawContainerURL.standardizedFileURL
        guard containerURL.isFileURL,
              containerURL.path.hasPrefix("/"),
              containerURL.path != "/",
              rootValidator(containerURL) else {
            throw WallpaperLabError.unsafeContainerRoot
        }
        try validateDirectory(containerURL, fileManager: fileManager)

        let storeURL = containerURL.appendingPathComponent(
            storeRelativePath,
            isDirectory: true
        )
        guard isContained(storeURL, in: containerURL),
              fileManager.fileExists(atPath: storeURL.path) else {
            throw WallpaperLabError.posterStoreUnavailable
        }
        try validatePathComponents(
            relativePath: storeRelativePath,
            root: containerURL,
            fileManager: fileManager
        )

        let generationURLs = try fileManager.contentsOfDirectory(
            at: storeURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard Int(url.lastPathComponent) != nil else { return false }
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            return values?.isDirectory == true && values?.isSymbolicLink != true
        }.sorted {
            (Int($0.lastPathComponent) ?? -1) > (Int($1.lastPathComponent) ?? -1)
        }

        guard !generationURLs.isEmpty else {
            throw WallpaperLabError.unsupportedPosterLayout
        }

        for generationURL in generationURLs {
            let extensionsURL = generationURL.appendingPathComponent("Extensions", isDirectory: true)
            guard fileManager.fileExists(atPath: extensionsURL.path) else { continue }
            try validateDirectory(extensionsURL, fileManager: fileManager)

            var descriptorDirectories: [String: URL] = [:]
            let extensions = try fileManager.contentsOfDirectory(
                at: extensionsURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            for extensionURL in extensions {
                let values = try extensionURL.resourceValues(
                    forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
                )
                guard values.isDirectory == true, values.isSymbolicLink != true else { continue }
                guard validExtensionIdentifier(extensionURL.lastPathComponent) else { continue }
                let descriptorsURL = extensionURL.appendingPathComponent(
                    "descriptors",
                    isDirectory: true
                )
                guard fileManager.fileExists(atPath: descriptorsURL.path) else { continue }
                try validateDirectory(descriptorsURL, fileManager: fileManager)
                descriptorDirectories[extensionURL.lastPathComponent] = descriptorsURL
            }

            if !descriptorDirectories.isEmpty {
                return WallpaperPosterLayout(
                    generation: generationURL.lastPathComponent,
                    storeURL: storeURL,
                    extensionDescriptorDirectories: descriptorDirectories
                )
            }
        }
        throw WallpaperLabError.unsupportedPosterLayout
    }

    static func validExtensionIdentifier(_ value: String) -> Bool {
        guard !value.isEmpty, value.utf8.count <= 255, value.contains(".") else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_"))
        return value.unicodeScalars.allSatisfy(allowed.contains)
    }

    static func validateDirectory(
        _ url: URL,
        fileManager: FileManager = .default
    ) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            throw WallpaperLabError.posterStoreUnavailable
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isSymbolicLink != true else {
            throw WallpaperLabError.symbolicLinkUnsupported
        }
        guard values.isDirectory == true else {
            throw WallpaperLabError.unsupportedPosterLayout
        }
    }

    static func validatePathComponents(
        relativePath: String,
        root: URL,
        fileManager: FileManager = .default
    ) throws {
        var cursor = root
        for component in relativePath.split(separator: "/").map(String.init) {
            cursor.appendPathComponent(component, isDirectory: true)
            guard isContained(cursor, in: root) else {
                throw WallpaperLabError.unsafeContainerRoot
            }
            try validateDirectory(cursor, fileManager: fileManager)
        }
    }

    static func isContained(_ candidate: URL, in root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let candidatePath = candidate.standardizedFileURL.path
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }
}

enum TendiesPackageInspector {

    static func resolveExtensionIdentifier(fromDirectoryName name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("video") || lower.contains("photos") || lower.contains("live") {
            return WallpaperPosterLayout.photosExtension
        }
        if lower.contains("mercury") {
            return WallpaperPosterLayout.mercuryExtension
        }
        if lower.contains("weather") {
            return WallpaperPosterLayout.weatherExtension
        }
        if lower.contains("astronomy") || lower.contains("space") || lower.contains("planet") {
            return WallpaperPosterLayout.astronomyExtension
        }
        if lower.contains("pride") || lower.contains("rainbow") {
            return WallpaperPosterLayout.prideExtension
        }
        if lower.contains("unity") {
            return WallpaperPosterLayout.unityExtension
        }
        if lower.contains("emoji") {
            return WallpaperPosterLayout.emojiExtension
        }
        if lower.contains("color") || lower.contains("solid") {
            return WallpaperPosterLayout.colorExtension
        }
        if lower.contains("gradient") {
            return WallpaperPosterLayout.gradientExtension
        }
        if lower.contains("kaleidoscope") {
            return WallpaperPosterLayout.kaleidoscopeExtension
        }
        return WallpaperPosterLayout.collectionsExtension
    }

    static func inspectExtractedPackage(
        at packageURL: URL,
        fileManager: FileManager = .default
    ) throws -> TendiesPayload {
        try WallpaperLayoutScanner.validateDirectory(packageURL, fileManager: fileManager)
        let descriptors = try collectDescriptorSources(
            in: packageURL,
            packageRoot: packageURL,
            fileManager: fileManager
        )

        guard !descriptors.isEmpty else { throw WallpaperLabError.noDescriptors }
        guard descriptors.count <= WallpaperLabLimits.maximumDescriptorCount else {
            throw WallpaperLabError.packageTooLarge
        }
        let totalBytes = descriptors.reduce(Int64(0)) { $0 + $1.byteCount }
        let fileCount = descriptors.reduce(0) { $0 + $1.fileCount }
        guard totalBytes <= WallpaperLabLimits.maximumExpandedBytes,
              fileCount <= WallpaperLabLimits.maximumEntryCount else {
            throw WallpaperLabError.packageTooLarge
        }
        return TendiesPayload(
            descriptors: descriptors,
            totalBytes: totalBytes,
            fileCount: fileCount
        )
    }

    private static func collectDescriptorSources(
        in directory: URL,
        packageRoot: URL,
        fileManager: FileManager
    ) throws -> [WallpaperDescriptorSource] {
        guard WallpaperLayoutScanner.isContained(directory, in: packageRoot) else {
            throw WallpaperLabError.unsafeArchive
        }
        try WallpaperLayoutScanner.validateDirectory(directory, fileManager: fileManager)
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [WallpaperDescriptorSource] = []

        for child in children where child.lastPathComponent != "__MACOSX" {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            guard values.isDirectory == true else { continue }

            let name = child.lastPathComponent.lowercased()
            if name == "container" {
                let layout = try WallpaperLayoutScanner.scan(
                    containerURL: child,
                    rootValidator: { $0.standardizedFileURL == child.standardizedFileURL },
                    fileManager: fileManager
                )
                for (identifier, descriptorDirectory) in layout.extensionDescriptorDirectories
                    .sorted(by: { $0.key < $1.key }) {
                    result += try descriptorSources(
                        in: descriptorDirectory,
                        extensionIdentifier: identifier,
                        isOrdered: false,
                        packageRoot: packageRoot,
                        fileManager: fileManager
                    )
                }
            } else if name.contains("descriptor") {
                let extensionIdentifier = Self.resolveExtensionIdentifier(fromDirectoryName: name)
                result += try descriptorSources(
                    in: child,
                    extensionIdentifier: extensionIdentifier,
                    isOrdered: name.contains("ordered"),
                    packageRoot: packageRoot,
                    fileManager: fileManager
                )
            } else {
                result += try collectDescriptorSources(
                    in: child,
                    packageRoot: packageRoot,
                    fileManager: fileManager
                )
            }
        }
        return result
    }

    private static func descriptorSources(
        in directory: URL,
        extensionIdentifier: String,
        isOrdered: Bool,
        packageRoot: URL,
        fileManager: FileManager
    ) throws -> [WallpaperDescriptorSource] {
        guard WallpaperLayoutScanner.validExtensionIdentifier(extensionIdentifier),
              WallpaperLayoutScanner.isContained(directory, in: packageRoot) else {
            throw WallpaperLabError.unsafeArchive
        }
        try WallpaperLayoutScanner.validateDirectory(directory, fileManager: fileManager)
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ).sorted { $0.lastPathComponent < $1.lastPathComponent }
        var result: [WallpaperDescriptorSource] = []
        for child in children where child.lastPathComponent != "__MACOSX" {
            let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true else {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            guard values.isDirectory == true else { continue }
            let summary = try validateTree(
                at: child,
                packageRoot: packageRoot,
                fileManager: fileManager
            )
            result.append(
                WallpaperDescriptorSource(
                    extensionIdentifier: extensionIdentifier,
                    directoryURL: child,
                    byteCount: summary.bytes,
                    fileCount: summary.files,
                    isOrdered: isOrdered
                )
            )
        }
        return result
    }

    private static func validateTree(
        at directory: URL,
        packageRoot: URL,
        fileManager: FileManager
    ) throws -> (bytes: Int64, files: Int) {
        guard WallpaperLayoutScanner.isContained(directory, in: packageRoot) else {
            throw WallpaperLabError.unsafeArchive
        }
        var bytes: Int64 = 0
        var files = 0
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw WallpaperLabError.unsupportedPackage
        }
        for case let itemURL as URL in enumerator {
            guard WallpaperLayoutScanner.isContained(itemURL, in: packageRoot),
                  itemURL.path.utf8.count <= WallpaperLabLimits.maximumPathBytes else {
                throw WallpaperLabError.unsafeArchive
            }
            let values = try itemURL.resourceValues(forKeys: [
                .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey
            ])
            if values.isSymbolicLink == true {
                throw WallpaperLabError.symbolicLinkUnsupported
            }
            if values.isRegularFile == true {
                let size = Int64(values.fileSize ?? 0)
                guard size >= 0, size <= WallpaperLabLimits.maximumEntryBytes else {
                    throw WallpaperLabError.packageTooLarge
                }
                bytes += size
                files += 1
                guard bytes <= WallpaperLabLimits.maximumExpandedBytes,
                      files <= WallpaperLabLimits.maximumEntryCount else {
                    throw WallpaperLabError.packageTooLarge
                }
            } else if values.isDirectory != true {
                throw WallpaperLabError.unsupportedPackage
            }
        }
        return (bytes, files)
    }
}

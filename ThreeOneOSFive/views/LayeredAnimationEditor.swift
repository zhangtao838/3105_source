import SwiftUI
import UniformTypeIdentifiers

struct LayeredAnimationEditorView: View {
    @State private var package: WallpaperStagedPackage?
    @State private var showPicker = false
    @State private var layers: [AnimationLayer] = []
    @State private var selectedLayer: AnimationLayer?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showExport = false
    @State private var exportURL: URL?
    @State private var caBundleURL: URL?
    @State private var camlURL: URL?
    @State private var originalCAMLContent: String = ""

    var body: some View {
        NavigationStack {
            Group {
                if package == nil {
                    emptyState
                } else {
                    editorContent
                }
            }
            .navigationTitle("分层动画编辑器")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showPicker = true } label: {
                            Label("打开壁纸包", systemImage: "folder")
                        }
                        if package != nil && !layers.isEmpty {
                            Button { exportPackage() } label: {
                                Label("导出修改后的包", systemImage: "square.and.arrow.up")
                            }
                        }
                        if package != nil {
                            Button(role: .destructive) {
                                package = nil
                                layers = []
                                caBundleURL = nil
                                camlURL = nil
                            } label: {
                                Label("关闭", systemImage: "xmark")
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                FileDocumentPicker(
                    allowedContentTypes: [UTType(filenameExtension: "tendies") ?? .data, .data],
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showPicker = false
                        if case .success(let urls) = result, let url = urls.first {
                            loadPackage(url)
                        }
                    },
                    onCancel: { showPicker = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showExport) {
                if let url = exportURL {
                    ActivityViewController(activityItems: [url])
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.5))
            Text("分层动画编辑器")
                .font(.title2.weight(.bold))
            Text("打开一个 .tendies 壁纸包，编辑其中的 LayeredAnimation 分层动画（main.caml）")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button {
                showPicker = true
            } label: {
                Label("选择壁纸包", systemImage: "folder.badge.plus")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(red: 0.42, green: 0.36, blue: 0.91))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.96, blue: 0.98).ignoresSafeArea())
    }

    private var editorContent: some View {
        VStack(spacing: 0) {
            if let pkg = package {
                HStack {
                    Image(systemName: "doc.zipper")
                        .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.91))
                    Text(pkg.displayName)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Spacer()
                    Text("\(layers.count) 图层")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.white)
            }

            if isLoading {
                ProgressView("正在解析...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if layers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.stack")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("未找到 LayeredAnimation 图层")
                        .font(.subheadline)
                    Text("这个壁纸包可能不包含分层动画（.ca bundle / main.caml）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(layers) { layer in
                        LayerRow(layer: layer, isSelected: selectedLayer?.id == layer.id) {
                            selectedLayer = layer
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }

            if selectedLayer != nil {
                layerEditorPanel
            }
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.98).ignoresSafeArea())
    }

    private var layerEditorPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("编辑图层")
                    .font(.headline)
                Spacer()
                Button {
                    selectedLayer = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }

            if let layer = selectedLayer {
                HStack(spacing: 12) {
                    if let image = layer.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 60, height: 60)
                            .cornerRadius(8)
                            .background(Color.gray.opacity(0.1))
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                            .frame(width: 60, height: 60)
                            .overlay(Image(systemName: "photo").foregroundStyle(.gray))
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(layer.name)
                            .font(.subheadline.weight(.medium))
                        Text(layer.imageName ?? "无关联图片")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        sliderRow(title: "位置 X", value: Binding(
                            get: { layer.positionX },
                            set: { newValue in updateLayer(layer) { $0.positionX = newValue } }
                        ), range: -300...300)

                        sliderRow(title: "位置 Y", value: Binding(
                            get: { layer.positionY },
                            set: { newValue in updateLayer(layer) { $0.positionY = newValue } }
                        ), range: -300...300)

                        sliderRow(title: "缩放", value: Binding(
                            get: { layer.scale },
                            set: { newValue in updateLayer(layer) { $0.scale = newValue } }
                        ), range: 0.1...3.0)

                        sliderRow(title: "透明度", value: Binding(
                            get: { layer.opacity },
                            set: { newValue in updateLayer(layer) { $0.opacity = newValue } }
                        ), range: 0...1)

                        sliderRow(title: "旋转角度", value: Binding(
                            get: { layer.rotation },
                            set: { newValue in updateLayer(layer) { $0.rotation = newValue } }
                        ), range: -180...180)
                    }
                }
                .frame(maxHeight: 200)

                HStack {
                    Button {
                        exportPackage()
                    } label: {
                        Label("保存并导出", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.42, green: 0.36, blue: 0.91))
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.2f", value.wrappedValue))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func loadPackage(_ url: URL) {
        isLoading = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let pkg = try WallpaperPackageStore.importPackage(from: url)
                let (parsedLayers, caURL, camlPath, camlContent) = try parseLayers(from: pkg)
                DispatchQueue.main.async {
                    package = pkg
                    layers = parsedLayers
                    caBundleURL = caURL
                    camlURL = camlPath
                    originalCAMLContent = camlContent
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func parseLayers(from package: WallpaperStagedPackage) throws -> (
        layers: [AnimationLayer],
        caBundleURL: URL?,
        camlURL: URL?,
        camlContent: String
    ) {
        var layers: [AnimationLayer] = []
        var caBundle: URL?
        var camlFile: URL?
        var camlContent = ""
        let fm = FileManager.default

        for descriptor in package.payload.descriptors {
            let dir = descriptor.directoryURL
            guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "ca" {
                    caBundle = fileURL
                }
                if fileURL.lastPathComponent == "main.caml" {
                    camlFile = fileURL
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        camlContent = content
                    }
                }
            }
        }

        if let caBundle = caBundle {
            let assetsDir = caBundle.appendingPathComponent("assets", isDirectory: true)
            if fm.fileExists(atPath: assetsDir.path),
               let assets = try? fm.contentsOfDirectory(at: assetsDir, includingPropertiesForKeys: nil) {
                let images = assets.filter { ["png", "jpg", "jpeg", "heic", "webp"].contains($0.pathExtension.lowercased()) }
                for (index, imgURL) in images.enumerated() {
                    let image = UIImage(contentsOfFile: imgURL.path)
                    layers.append(AnimationLayer(
                        id: UUID(),
                        name: imgURL.deletingPathExtension().lastPathComponent,
                        imageName: imgURL.lastPathComponent,
                        imageURL: imgURL,
                        previewImage: image,
                        index: index,
                        positionX: 0,
                        positionY: 0,
                        scale: 1.0,
                        opacity: 1.0,
                        rotation: 0
                    ))
                }
            }
        }

        if !camlContent.isEmpty {
            let parsed = parseCAMLXML(camlContent, caBundle: caBundle)
            if !parsed.isEmpty {
                layers = parsed
            }
        }

        return (layers, caBundle, camlFile, camlContent)
    }

    private func parseCAMLXML(_ content: String, caBundle: URL?) -> [AnimationLayer] {
        var layers: [AnimationLayer] = []
        let fm = FileManager.default

        let layerPattern = "<CALayer\\s+([^>]+)>"
        guard let regex = try? NSRegularExpression(pattern: layerPattern, options: []) else { return layers }
        let matches = regex.matches(in: content, range: NSRange(content.startIndex..., in: content))

        var layerIndex = 0
        for match in matches {
            guard let attrRange = Range(match.range(at: 1), in: content) else { continue }
            let attrs = String(content[attrRange])

            let id = extractXMLAttr("id", from: attrs)
            let name = extractXMLAttr("name", from: attrs)
            let position = extractXMLAttr("position", from: attrs)
            let bounds = extractXMLAttr("bounds", from: attrs)
            let opacityStr = extractXMLAttr("opacity", from: attrs)
            let rotationStr = extractXMLAttr("transform.rotation.z", from: attrs)

            let posComponents = position?.components(separatedBy: .whitespaces).compactMap { Double($0) } ?? []
            let posX = posComponents.count >= 1 ? posComponents[0] : 0
            let posY = posComponents.count >= 2 ? posComponents[1] : 0

            let boundsComponents = bounds?.components(separatedBy: .whitespaces).compactMap { Double($0) } ?? []
            let width = boundsComponents.count >= 3 ? boundsComponents[2] : 100
            let scale = width > 0 ? width / 100.0 : 1.0

            let opacity = Double(opacityStr ?? "1") ?? 1.0
            let rotation = (Double(rotationStr ?? "0") ?? 0) * 180 / .pi

            var imageName: String?
            var imageURL: URL?
            var previewImage: UIImage?

            if let caBundle = caBundle {
                let contentsPattern = "CGImage\\s+src=\"([^\"]+)\""
                if let contentsRegex = try? NSRegularExpression(pattern: contentsPattern, options: []),
                   let layerStart = content.range(of: attrs)?.lowerBound,
                   let afterLayer = content[layerStart...].range(of: "</CALayer>")?.lowerBound {
                    let layerContent = String(content[layerStart..<afterLayer])
                    if let cMatch = contentsRegex.firstMatch(in: layerContent, range: NSRange(layerContent.startIndex..., in: layerContent)),
                       let srcRange = Range(cMatch.range(at: 1), in: layerContent) {
                        let src = String(layerContent[srcRange])
                        imageName = (src as NSString).lastPathComponent
                        imageURL = caBundle.appendingPathComponent(src)
                        if fm.fileExists(atPath: imageURL!.path) {
                            previewImage = UIImage(contentsOfFile: imageURL!.path)
                        }
                    }
                }
            }

            layers.append(AnimationLayer(
                id: UUID(),
                name: (name?.isEmpty ?? true) ? "图层 \(layerIndex + 1)" : name!,
                imageName: imageName,
                imageURL: imageURL,
                previewImage: previewImage,
                index: layerIndex,
                positionX: posX,
                positionY: posY,
                scale: scale,
                opacity: opacity,
                rotation: rotation
            ))
            layerIndex += 1
        }

        return layers
    }

    private func extractXMLAttr(_ name: String, from attrs: String) -> String? {
        let pattern = "\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
              let match = regex.firstMatch(in: attrs, range: NSRange(attrs.startIndex..., in: attrs)),
              let range = Range(match.range(at: 1), in: attrs) else { return nil }
        return String(attrs[range])
    }

    private func updateLayer(_ layer: AnimationLayer, transform: (inout AnimationLayer) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        var updated = layers[index]
        transform(&updated)
        layers[index] = updated
        selectedLayer = updated
    }

    private func exportPackage() {
        guard let pkg = package else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("wlp-export-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: tempDir) }

                let sourceDir = pkg.archiveURL.deletingLastPathComponent().appendingPathComponent("extracted", isDirectory: true)
                let workDir = tempDir.appendingPathComponent("package", isDirectory: true)
                try FileManager.default.copyItem(at: sourceDir, to: workDir)

                if let camlURL = camlURL {
                    let newCAML = generateCAML(from: layers, original: originalCAMLContent)
                    let relativePath = camlURL.path.replacingOccurrences(of: sourceDir.path, with: "")
                    let targetURL = workDir.appendingPathComponent(relativePath)
                    try? newCAML.write(to: targetURL, atomically: true, encoding: .utf8)
                }

                let outputURL = tempDir.appendingPathComponent("\(pkg.displayName)-edited.tendies")
                let coordinator = NSFileCoordinator()
                var error: NSError?
                coordinator.coordinate(readingItemAt: workDir, options: .forUploading, error: &error) { zipURL in
                    try? FileManager.default.removeItem(at: outputURL)
                    try? FileManager.default.copyItem(at: zipURL, to: outputURL)
                }

                DispatchQueue.main.async {
                    isLoading = false
                    exportURL = outputURL
                    showExport = true
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading = false
                    errorMessage = "导出失败: \(error.localizedDescription)"
                }
            }
        }
    }

    private func generateCAML(from layers: [AnimationLayer], original: String) -> String {
        var result = original
        for layer in layers {
            guard let imageName = layer.imageName else { continue }
            let pattern = "<CALayer\\s+[^>]*name=\"\(NSRegularExpression.escapedPattern(for: imageName))\"[^>]*>"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []),
                  let match = regex.firstMatch(in: result, range: NSRange(result.startIndex..., in: result)),
                  let range = Range(match.range, in: result) else { continue }

            let tag = String(result[range])
            var newTag = tag

            newTag = updateXMLAttr("position", in: newTag, value: "\(layer.positionX) \(layer.positionY)")
            newTag = updateXMLAttr("opacity", in: newTag, value: "\(layer.opacity)")
            newTag = updateXMLAttr("transform.rotation.z", in: newTag, value: "\(layer.rotation * .pi / 180)")

            result = result.replacingCharacters(in: range, with: newTag)
        }
        return result
    }

    private func updateXMLAttr(_ name: String, in tag: String, value: String) -> String {
        let pattern = "\(name)=\"[^\"]*\""
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           let match = regex.firstMatch(in: tag, range: NSRange(tag.startIndex..., in: tag)),
           let range = Range(match.range, in: tag) {
            return tag.replacingCharacters(in: range, with: "\(name)=\"\(value)\"")
        }
        return tag
    }
}

struct AnimationLayer: Identifiable, Equatable {
    let id: UUID
    var name: String
    var imageName: String?
    var imageURL: URL?
    var previewImage: UIImage?
    var index: Int
    var positionX: Double
    var positionY: Double
    var scale: Double
    var opacity: Double
    var rotation: Double

    static func == (lhs: AnimationLayer, rhs: AnimationLayer) -> Bool {
        lhs.id == rhs.id
    }
}

struct LayerRow: View {
    let layer: AnimationLayer
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Group {
                    if let image = layer.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 44, height: 44)
                            .cornerRadius(8)
                            .clipped()
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.15))
                            .frame(width: 44, height: 44)
                            .overlay(Image(systemName: "square.2.layers.3d").foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.91)))
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(layer.imageName ?? "无图片")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("缩放: \(String(format: "%.2f", layer.scale)) · 透明度: \(String(format: "%.0f%%", layer.opacity * 100))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color(red: 0.42, green: 0.36, blue: 0.91) : .gray)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.08) : Color.white)
    }
}

struct ActivityViewController: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension String {
    func matches(for regex: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: regex) else { return [] }
        let results = regex.matches(in: self, range: NSRange(self.startIndex..., in: self))
        return results.compactMap {
            guard let range = Range($0.range, in: self) else { return nil }
            return String(self[range])
        }
    }
}

extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners
    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(roundedRect: rect, byRoundingCorners: corners, cornerRadii: CGSize(width: radius, height: radius))
        return Path(path.cgPath)
    }
}

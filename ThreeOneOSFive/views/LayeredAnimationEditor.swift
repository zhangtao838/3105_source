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
                    if let bundleContents = try? fm.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: nil) {
                        let images = bundleContents.filter { ["png", "jpg", "jpeg", "heic", "webp"].contains($0.pathExtension.lowercased()) }
                        for (index, imgURL) in images.enumerated() {
                            let image = UIImage(contentsOfFile: imgURL.path)
                            layers.append(AnimationLayer(
                                id: UUID(),
                                name: "图层 \(index + 1)",
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
                if fileURL.pathExtension == "caml" {
                    camlFile = fileURL
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        camlContent = content
                        let parsed = parseCAML(content, caBundle: caBundle)
                        if !parsed.isEmpty {
                            layers = parsed
                        }
                    }
                }
            }
        }
        return (layers, caBundle, camlFile, camlContent)
    }

    private func parseCAML(_ content: String, caBundle: URL?) -> [AnimationLayer] {
        var layers: [AnimationLayer] = []
        let lines = content.components(separatedBy: .newlines)
        var layerIndex = 0
        var currentName = ""
        var currentContents = ""
        var currentPosX = 0.0
        var currentPosY = 0.0
        var currentScale = 1.0
        var currentOpacity = 1.0
        var currentRotation = 0.0
        var inLayer = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.contains("addSublayer") || trimmed.contains("layer = {") {
                if inLayer && !currentContents.isEmpty {
                    let imageURL = caBundle?.appendingPathComponent(currentContents)
                    let image = imageURL.flatMap { UIImage(contentsOfFile: $0.path) }
                    layers.append(AnimationLayer(
                        id: UUID(),
                        name: currentName.isEmpty ? "图层 \(layerIndex + 1)" : currentName,
                        imageName: currentContents,
                        imageURL: imageURL,
                        previewImage: image,
                        index: layerIndex,
                        positionX: currentPosX,
                        positionY: currentPosY,
                        scale: currentScale,
                        opacity: currentOpacity,
                        rotation: currentRotation
                    ))
                    layerIndex += 1
                }
                inLayer = true
                currentName = ""
                currentContents = ""
                currentPosX = 0
                currentPosY = 0
                currentScale = 1
                currentOpacity = 1
                currentRotation = 0
            }
            if trimmed.hasPrefix("name") {
                currentName = extractStringValue(from: trimmed)
            }
            if trimmed.hasPrefix("contents") {
                currentContents = extractStringValue(from: trimmed)
            }
            if trimmed.hasPrefix("position") {
                let pos = extractPoint(from: trimmed)
                currentPosX = pos.x
                currentPosY = pos.y
            }
            if trimmed.hasPrefix("opacity") {
                currentOpacity = extractDouble(from: trimmed) ?? 1.0
            }
            if trimmed.contains("scale") {
                currentScale = extractDouble(from: trimmed) ?? 1.0
            }
            if trimmed.contains("rotation") || trimmed.contains("zRotation") {
                currentRotation = (extractDouble(from: trimmed) ?? 0) * 180 / .pi
            }
        }

        if inLayer && !currentContents.isEmpty {
            let imageURL = caBundle?.appendingPathComponent(currentContents)
            let image = imageURL.flatMap { UIImage(contentsOfFile: $0.path) }
            layers.append(AnimationLayer(
                id: UUID(),
                name: currentName.isEmpty ? "图层 \(layerIndex + 1)" : currentName,
                imageName: currentContents,
                imageURL: imageURL,
                previewImage: image,
                index: layerIndex,
                positionX: currentPosX,
                positionY: currentPosY,
                scale: currentScale,
                opacity: currentOpacity,
                rotation: currentRotation
            ))
        }

        return layers
    }

    private func extractStringValue(from line: String) -> String {
        if let range = line.range(of: "\"[^\"]+\"", options: .regularExpression) {
            return String(line[range]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        return ""
    }

    private func extractDouble(from line: String) -> Double? {
        if let range = line.range(of: "-?\\d+\\.?\\d*", options: .regularExpression) {
            return Double(String(line[range]))
        }
        return nil
    }

    private func extractPoint(from line: String) -> (x: Double, y: Double) {
        let numbers = line.matches(for: "-?\\d+\\.?\\d*").compactMap { Double($0) }
        if numbers.count >= 2 {
            return (numbers[0], numbers[1])
        }
        return (0, 0)
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
            if let imageName = layer.imageName {
                let pattern = "contents\\s*=\\s*\"\(NSRegularExpression.escapedPattern(for: imageName))\""
                if let range = result.range(of: pattern, options: .regularExpression) {
                    let layerBlock = extractLayerBlock(containing: range, in: result)
                    if !layerBlock.isEmpty {
                        var newBlock = layerBlock
                        newBlock = updateKey("position", in: newBlock, value: "{\(layer.positionX), \(layer.positionY)}")
                        newBlock = updateKey("opacity", in: newBlock, value: "\(layer.opacity)")
                        newBlock = updateKey("transform.scale", in: newBlock, value: "\(layer.scale)")
                        newBlock = updateKey("transform.rotation", in: newBlock, value: "\(layer.rotation * .pi / 180)")
                        result = result.replacingOccurrences(of: layerBlock, with: newBlock)
                    }
                }
            }
        }
        return result
    }

    private func extractLayerBlock(containing range: Range<String.Index>, in text: String) -> String {
        var start = range.lowerBound
        var braceCount = 0
        var foundStart = false
        while start > text.startIndex {
            let char = text[text.index(before: start)]
            if char == "}" && foundStart { break }
            if char == "{" {
                braceCount += 1
                foundStart = true
            }
            start = text.index(before: start)
            if foundStart && braceCount == 0 { break }
        }
        var end = range.upperBound
        braceCount = 0
        while end < text.endIndex {
            let char = text[end]
            if char == "{" { braceCount += 1 }
            if char == "}" {
                if braceCount == 0 {
                    end = text.index(after: end)
                    break
                }
                braceCount -= 1
            }
            end = text.index(after: end)
        }
        return String(text[start..<end])
    }

    private func updateKey(_ key: String, in block: String, value: String) -> String {
        let patterns = [
            "\(key)\\s*=\\s*[^;]+;",
            "\(key)\\s*=\\s*\\{[^}]+\\};"
        ]
        for pattern in patterns {
            if let range = block.range(of: pattern, options: .regularExpression) {
                return block.replacingCharacters(in: range, with: "\(key) = \(value);")
            }
        }
        return block
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

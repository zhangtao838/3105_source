import SwiftUI
import UniformTypeIdentifiers

struct LayeredAnimationEditorView: View {
    @State private var package: WallpaperStagedPackage?
    @State private var showPicker = false
    @State private var layers: [AnimationLayer] = []
    @State private var selectedLayerID: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showExport = false
    @State private var exportURL: URL?
    @State private var caBundleURL: URL?
    @State private var camlURL: URL?
    @State private var originalCAMLContent: String = ""
    @State private var currentTab: EditorTab = .layers
    @State private var canvasScale: CGFloat = 1.0
    @State private var isDragging = false

    enum EditorTab {
        case layers
        case properties
    }

    var selectedLayer: AnimationLayer? {
        layers.first { $0.id == selectedLayerID }
    }

    var body: some View {
        NavigationStack {
            Group {
                if package == nil {
                    emptyState
                } else {
                    VStack(spacing: 0) {
                        previewCanvas
                        tabBar
                        tabContent
                    }
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
                                selectedLayerID = nil
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

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.5))
            Text("分层动画编辑器")
                .font(.title2.weight(.bold))
            Text("打开 .tendies 壁纸包，可视化编辑分层动画\n支持拖动、缩放、旋转、透明度调节")
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

    // MARK: - Preview Canvas

    private var previewCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color(red: 0.15, green: 0.15, blue: 0.18)
                    .cornerRadius(12)

                if isLoading {
                    ProgressView("正在解析...")
                        .tint(.white)
                } else if let error = errorMessage {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 20)
                    }
                } else if layers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.stack")
                            .font(.largeTitle)
                            .foregroundStyle(.white.opacity(0.4))
                        Text("未找到图层")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                } else {
                    let canvasSize = geometry.size
                    let baseWidth: CGFloat = 390
                    let baseHeight: CGFloat = 844
                    let scale = min(canvasSize.width / baseWidth, canvasSize.height / baseHeight) * 0.9
                    let offsetX = (canvasSize.width - baseWidth * scale) / 2
                    let offsetY = (canvasSize.height - baseHeight * scale) / 2

                    ZStack {
                        ForEach(layers) { layer in
                            LayerPreviewView(
                                layer: layer,
                                isSelected: layer.id == selectedLayerID,
                                scale: scale
                            )
                            .offset(x: offsetX + (layer.positionX - layer.boundsWidth / 2) * scale,
                                    y: offsetY + (layer.positionY - layer.boundsHeight / 2) * scale)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        isDragging = true
                                        selectedLayerID = layer.id
                                        let newX = layer.positionX + value.translation.width / scale
                                        let newY = layer.positionY + value.translation.height / scale
                                        updateLayer(layer) { $0.positionX = newX; $0.positionY = newY }
                                    }
                                    .onEnded { _ in
                                        isDragging = false
                                    }
                            )
                            .onTapGesture {
                                selectedLayerID = layer.id
                                currentTab = .properties
                            }
                        }
                    }

                    VStack {
                        HStack {
                            Text("\(layers.count) 图层")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            if isDragging {
                                Text("拖动中...")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                        Spacer()
                    }
                }
            }
            .padding(8)
            .frame(height: UIScreen.main.bounds.height * 0.42)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(title: "图层", icon: "square.stack.3d.down.forward", tab: .layers)
            tabButton(title: "属性", icon: "slider.horizontal.3", tab: .properties)
        }
        .frame(height: 44)
        .background(Color.white)
    }

    private func tabButton(title: String, icon: String, tab: EditorTab) -> some View {
        Button {
            currentTab = tab
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(currentTab == tab ? Color(red: 0.42, green: 0.36, blue: 0.91) : .gray)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                if currentTab == tab {
                    Rectangle()
                        .fill(Color(red: 0.42, green: 0.36, blue: 0.91))
                        .frame(height: 2)
                }
            }
        }
    }

    // MARK: - Tab Content

    @ViewBuilder
    private var tabContent: some View {
        switch currentTab {
        case .layers:
            layersList
        case .properties:
            propertiesPanel
        }
    }

    // MARK: - Layers List

    private var layersList: some View {
        List {
            if layers.isEmpty {
                ContentUnavailableView("无图层", systemImage: "square.stack", description: Text("这个壁纸包不包含可编辑的图层"))
            } else {
                ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
                    LayerListRow(
                        layer: layer,
                        index: index,
                        isSelected: layer.id == selectedLayerID,
                        onSelect: { selectedLayerID = layer.id; currentTab = .properties },
                        onDelete: { deleteLayer(layer) },
                        onMoveUp: { moveLayer(layer, direction: -1) },
                        onMoveDown: { moveLayer(layer, direction: 1) }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .frame(maxHeight: .infinity)
    }

    // MARK: - Properties Panel

    private var propertiesPanel: some View {
        ScrollView {
            if let layer = selectedLayer {
                VStack(alignment: .leading, spacing: 16) {
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
                                .font(.headline)
                            Text(layer.imageName ?? "无图片")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("尺寸: \(Int(layer.boundsWidth))×\(Int(layer.boundsHeight))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    Group {
                        propertySlider(title: "位置 X", value: Binding(
                            get: { layer.positionX },
                            set: { newValue in updateLayer(layer) { $0.positionX = newValue } }
                        ), range: -500...500, unit: "pt")

                        propertySlider(title: "位置 Y", value: Binding(
                            get: { layer.positionY },
                            set: { newValue in updateLayer(layer) { $0.positionY = newValue } }
                        ), range: -500...1500, unit: "pt")

                        propertySlider(title: "缩放", value: Binding(
                            get: { layer.scale },
                            set: { newValue in updateLayer(layer) { $0.scale = newValue } }
                        ), range: 0.1...3.0, unit: "x")

                        propertySlider(title: "透明度", value: Binding(
                            get: { layer.opacity },
                            set: { newValue in updateLayer(layer) { $0.opacity = newValue } }
                        ), range: 0...1, unit: "%")

                        propertySlider(title: "旋转", value: Binding(
                            get: { layer.rotation },
                            set: { newValue in updateLayer(layer) { $0.rotation = newValue } }
                        ), range: -180...180, unit: "°")
                    }
                    .padding(.horizontal, 16)

                    HStack(spacing: 12) {
                        Button {
                            resetLayer(layer)
                        } label: {
                            Label("重置", systemImage: "arrow.counterclockwise")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)

                        Button {
                            exportPackage()
                        } label: {
                            Label("保存并导出", systemImage: "square.and.arrow.up")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color(red: 0.42, green: 0.36, blue: 0.91))
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
                }
            } else {
                ContentUnavailableView("未选中图层", systemImage: "slider.horizontal.3", description: Text("在画布或图层列表中选择一个图层"))
            }
        }
        .frame(maxHeight: .infinity)
        .background(Color(red: 0.96, green: 0.96, blue: 0.98))
    }

    private func propertySlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(String(format: "%.1f", value.wrappedValue))\(unit)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .tint(Color(red: 0.42, green: 0.36, blue: 0.91))
        }
    }

    // MARK: - Layer Operations

    private func deleteLayer(_ layer: AnimationLayer) {
        layers.removeAll { $0.id == layer.id }
        if selectedLayerID == layer.id {
            selectedLayerID = nil
        }
    }

    private func moveLayer(_ layer: AnimationLayer, direction: Int) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        let newIndex = index + direction
        guard newIndex >= 0 && newIndex < layers.count else { return }
        layers.remove(at: index)
        layers.insert(layer, at: newIndex)
    }

    private func resetLayer(_ layer: AnimationLayer) {
        updateLayer(layer) { l in
            l.positionX = l.originalPositionX
            l.positionY = l.originalPositionY
            l.scale = l.originalScale
            l.opacity = l.originalOpacity
            l.rotation = l.originalRotation
        }
    }

    private func updateLayer(_ layer: AnimationLayer, transform: (inout AnimationLayer) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        var updated = layers[index]
        transform(&updated)
        layers[index] = updated
    }

    // MARK: - Package Loading

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
                    if !layers.isEmpty {
                        selectedLayerID = layers.first?.id
                    }
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
                    let size = image?.size ?? CGSize(width: 100, height: 100)
                    layers.append(AnimationLayer(
                        id: UUID(),
                        name: imgURL.deletingPathExtension().lastPathComponent,
                        imageName: imgURL.lastPathComponent,
                        imageURL: imgURL,
                        previewImage: image,
                        index: index,
                        positionX: 195,
                        positionY: 422,
                        boundsWidth: size.width,
                        boundsHeight: size.height,
                        scale: 1.0,
                        opacity: 1.0,
                        rotation: 0,
                        originalPositionX: 195,
                        originalPositionY: 422,
                        originalScale: 1.0,
                        originalOpacity: 1.0,
                        originalRotation: 0
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

            let id = extractXMLAttr("id", from: attrs) ?? ""
            if id == "__capRootLayer__" { continue }

            let name = extractXMLAttr("name", from: attrs) ?? ""
            let position = extractXMLAttr("position", from: attrs) ?? "0 0"
            let bounds = extractXMLAttr("bounds", from: attrs) ?? "0 0 100 100"
            let opacityStr = extractXMLAttr("opacity", from: attrs) ?? "1"
            let rotationStr = extractXMLAttr("transform.rotation.z", from: attrs) ?? "0"

            let posComponents = position.components(separatedBy: .whitespaces).compactMap { Double($0) }
            let posX = posComponents.count >= 1 ? posComponents[0] : 0
            let posY = posComponents.count >= 2 ? posComponents[1] : 0

            let boundsComponents = bounds.components(separatedBy: .whitespaces).compactMap { Double($0) }
            let width = boundsComponents.count >= 3 ? boundsComponents[2] : 100
            let height = boundsComponents.count >= 4 ? boundsComponents[3] : 100

            let opacity = Double(opacityStr) ?? 1.0
            let rotation = (Double(rotationStr) ?? 0) * 180 / .pi

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
                name: name.isEmpty ? "图层 \(layerIndex + 1)" : name,
                imageName: imageName,
                imageURL: imageURL,
                previewImage: previewImage,
                index: layerIndex,
                positionX: posX,
                positionY: posY,
                boundsWidth: width,
                boundsHeight: height,
                scale: 1.0,
                opacity: opacity,
                rotation: rotation,
                originalPositionX: posX,
                originalPositionY: posY,
                originalScale: 1.0,
                originalOpacity: opacity,
                originalRotation: rotation
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

    // MARK: - Export

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

// MARK: - Data Models

struct AnimationLayer: Identifiable, Equatable {
    let id: UUID
    var name: String
    var imageName: String?
    var imageURL: URL?
    var previewImage: UIImage?
    var index: Int
    var positionX: Double
    var positionY: Double
    var boundsWidth: Double
    var boundsHeight: Double
    var scale: Double
    var opacity: Double
    var rotation: Double
    var originalPositionX: Double
    var originalPositionY: Double
    var originalScale: Double
    var originalOpacity: Double
    var originalRotation: Double

    static func == (lhs: AnimationLayer, rhs: AnimationLayer) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Preview Views

struct LayerPreviewView: View {
    let layer: AnimationLayer
    let isSelected: Bool
    let scale: CGFloat

    var body: some View {
        Group {
            if let image = layer.previewImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .overlay(Image(systemName: "photo").foregroundStyle(.white))
            }
        }
        .frame(width: CGFloat(layer.boundsWidth) * scale * CGFloat(layer.scale),
               height: CGFloat(layer.boundsHeight) * scale * CGFloat(layer.scale))
        .opacity(layer.opacity)
        .rotationEffect(.degrees(layer.rotation))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .stroke(isSelected ? Color.yellow : Color.clear, lineWidth: 2)
        )
        .shadow(color: isSelected ? Color.yellow.opacity(0.5) : Color.clear, radius: 8)
    }
}

struct LayerListRow: View {
    let layer: AnimationLayer
    let index: Int
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void

    var body: some View {
        Button(action: onSelect) {
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
                    Text("位置: \(Int(layer.positionX)),\(Int(layer.positionY)) · 透明度: \(String(format: "%.0f%%", layer.opacity * 100))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 4) {
                    Button(action: onMoveUp) {
                        Image(systemName: "chevron.up")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .frame(width: 24, height: 24)
                    }
                    Button(action: onMoveDown) {
                        Image(systemName: "chevron.down")
                            .font(.caption)
                            .foregroundStyle(.gray)
                            .frame(width: 24, height: 24)
                    }
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .frame(width: 24, height: 24)
                    }
                }
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

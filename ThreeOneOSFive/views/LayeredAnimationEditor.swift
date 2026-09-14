import SwiftUI
import UniformTypeIdentifiers

struct LayeredAnimationEditorView: View {
    @State private var package: WallpaperStagedPackage?
    @State private var showPicker = false
    @State private var layers: [AnimationLayer] = []
    @State private var selectedLayer: AnimationLayer?
    @State private var isLoading = false
    @State private var errorMessage: String?

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
                        if package != nil {
                            Button(role: .destructive) {
                                package = nil
                                layers = []
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
                Text(layer.name)
                    .font(.subheadline.weight(.medium))

                VStack(alignment: .leading, spacing: 8) {
                    Text("位置 X")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { layer.positionX },
                        set: { newValue in updateLayer(layer) { $0.positionX = newValue } }
                    ), in: -200...200)

                    Text("位置 Y")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { layer.positionY },
                        set: { newValue in updateLayer(layer) { $0.positionY = newValue } }
                    ), in: -200...200)

                    Text("缩放")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { layer.scale },
                        set: { newValue in updateLayer(layer) { $0.scale = newValue } }
                    ), in: 0.5...2.0)

                    Text("透明度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { layer.opacity },
                        set: { newValue in updateLayer(layer) { $0.opacity = newValue } }
                    ), in: 0...1)

                    Text("旋转角度")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(
                        get: { layer.rotation },
                        set: { newValue in updateLayer(layer) { $0.rotation = newValue } }
                    ), in: -180...180)
                }

                HStack {
                    Button {
                        // 导出修改后的包
                    } label: {
                        Label("导出修改", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.42, green: 0.36, blue: 0.91))
                    .disabled(true)
                }

                Text("提示：当前为预览版，导出功能开发中")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16, corners: [.topLeft, .topRight])
        .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
    }

    private func loadPackage(_ url: URL) {
        isLoading = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let pkg = try WallpaperPackageStore.importPackage(from: url)
                let parsedLayers = try parseLayers(from: pkg)
                DispatchQueue.main.async {
                    package = pkg
                    layers = parsedLayers
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

    private func parseLayers(from package: WallpaperStagedPackage) throws -> [AnimationLayer] {
        var layers: [AnimationLayer] = []
        let fm = FileManager.default

        for descriptor in package.payload.descriptors {
            let dir = descriptor.directoryURL
            guard let enumerator = fm.enumerator(at: dir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for case let fileURL as URL in enumerator {
                if fileURL.pathExtension == "caml" {
                    // 解析 main.caml，提取图层信息
                    if let content = try? String(contentsOf: fileURL, encoding: .utf8) {
                        let parsed = parseCAML(content)
                        layers.append(contentsOf: parsed)
                    }
                }
                if fileURL.pathExtension == "ca" {
                    // .ca bundle 里的图片作为图层
                    if let bundleContents = try? fm.contentsOfDirectory(at: fileURL, includingPropertiesForKeys: nil) {
                        for (index, imgURL) in bundleContents.enumerated() where ["png", "jpg", "jpeg", "heic", "webp"].contains(imgURL.pathExtension.lowercased()) {
                            layers.append(AnimationLayer(
                                id: UUID(),
                                name: imgURL.lastPathComponent,
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
            }
        }
        return layers
    }

    private func parseCAML(_ content: String) -> [AnimationLayer] {
        // 简单解析 CAML 中的图层（addSublayer / contents）
        var layers: [AnimationLayer] = []
        let lines = content.components(separatedBy: .newlines)
        var layerIndex = 0
        for line in lines {
            if line.contains("addSublayer") || line.contains("contents") {
                let name = "图层 \(layerIndex + 1)"
                layers.append(AnimationLayer(
                    id: UUID(),
                    name: name,
                    index: layerIndex,
                    positionX: 0,
                    positionY: 0,
                    scale: 1.0,
                    opacity: 1.0,
                    rotation: 0
                ))
                layerIndex += 1
            }
        }
        return layers
    }

    private func updateLayer(_ layer: AnimationLayer, transform: (inout AnimationLayer) -> Void) {
        guard let index = layers.firstIndex(where: { $0.id == layer.id }) else { return }
        var updated = layers[index]
        transform(&updated)
        layers[index] = updated
        selectedLayer = updated
    }
}

struct AnimationLayer: Identifiable, Equatable {
    let id: UUID
    var name: String
    var index: Int
    var positionX: Double
    var positionY: Double
    var scale: Double
    var opacity: Double
    var rotation: Double
}

struct LayerRow: View {
    let layer: AnimationLayer
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: "square.2.layers.3d")
                        .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.91))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(layer.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
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

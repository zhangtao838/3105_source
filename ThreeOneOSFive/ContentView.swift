import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(\.appLanguage) private var language
    @EnvironmentObject private var repositoryStore: PackageRepositoryStore
    @State private var selectedTab = 0
    @State private var showSettings = false
    @State private var showLogs = false

    var body: some View {
        TabView(selection: $selectedTab) {
            WallpaperLibraryView(
                onOpenSettings: { showSettings = true },
                onOpenLogs: { showLogs = true }
            )
            .tabItem {
                Label("壁纸库", systemImage: "photo.stack.fill")
            }
            .tag(0)

            InstalledWallpapersTabView(
                onOpenSettings: { showSettings = true },
                onOpenLogs: { showLogs = true }
            )
            .tabItem {
                Label("已安装", systemImage: "checkmark.circle.fill")
            }
            .tag(1)

            WallpaperSettingsView(
                onOpenLogs: { showLogs = true }
            )
            .tabItem {
                Label("设置", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        .tint(Color(red: 0.42, green: 0.36, blue: 0.91))
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showLogs) { LogView() }
        .repositoryStorePresentation(repositoryStore, patchStore: PatchProjectStore())
    }
}

struct WallpaperLibraryView: View {
    @Environment(\.appLanguage) private var language
    @State private var report: WallpaperAccessReport?
    @State private var packages: [WallpaperStagedPackage] = []
    @State private var isBusy = false
    @State private var operationKey = "wallpaper.checking"
    @State private var showImporter = false
    @State private var showVideoImporter = false
    @State private var alert: WallpaperLabAlert?
    @State private var hasLoaded = false
    @State private var selectedPackage: WallpaperStagedPackage?
    @State private var showDetail = false

    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    headerBanner
                    quickActions
                    if packages.isEmpty {
                        emptyState
                    } else {
                        wallpaperGrid
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 100)
            }
            .background(Color(red: 0.96, green: 0.96, blue: 0.98).ignoresSafeArea())
            .navigationTitle("壁纸工坊")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button { showImporter = true } label: {
                            Label("导入 .tendies", systemImage: "square.and.arrow.down")
                        }
                        Button { showVideoImporter = true } label: {
                            Label("视频转壁纸", systemImage: "video.fill.badge.plus")
                        }
                        Divider()
                        Button(role: .destructive) {
                            alert = WallpaperLabAlert(kind: .resetAll)
                        } label: {
                            Label("重置全部自定义", systemImage: "arrow.counterclockwise")
                        }
                        .disabled(!(report?.canInstall ?? false) || isBusy)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .disabled(isBusy)
                }
                AppUtilityToolbar(
                    language: language,
                    onOpenSettings: onOpenSettings,
                    onOpenLogs: onOpenLogs
                )
            }
            .overlay { busyOverlay }
            .alert(item: $alert, content: alertContent)
            .sheet(isPresented: $showImporter) {
                FileDocumentPicker(
                    allowedContentTypes: [UTType(filenameExtension: "tendies") ?? .data, .data],
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: true,
                    onSelection: { result in
                        showImporter = false
                        if case .success(let urls) = result, !urls.isEmpty {
                            importPackages(urls)
                        }
                    },
                    onCancel: { showImporter = false }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $showVideoImporter) {
                FileDocumentPicker(
                    allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie, .video],
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showVideoImporter = false
                        if case .success(let urls) = result, let url = urls.first {
                            convertVideo(url)
                        }
                    },
                    onCancel: { showVideoImporter = false }
                )
                .ignoresSafeArea()
            }
            .navigationDestination(isPresented: $showDetail) {
                if let pkg = selectedPackage {
                    WallpaperDetailView(package: pkg, canInstall: report?.canInstall == true) {
                        alert = WallpaperLabAlert(kind: .install(pkg))
                    }
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                packages = WallpaperPackageStore.packages()
                checkAccess()
            }
        }
    }

    private var headerBanner: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report?.canInstall == true ? "访问就绪" : "只读模式")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.white)
                    Text(report?.canInstall == true ? "可以安装和管理壁纸" : "仅可查看，无法写入")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.85))
                }
                Spacer()
                Image(systemName: report?.canInstall == true ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white.opacity(0.9))
            }
            HStack(spacing: 16) {
                statItem(label: "描述符", value: "\(report?.descriptorCount ?? 0)")
                statItem(label: "自定义", value: "\(report?.customDescriptorCount ?? 0)")
                statItem(label: "类型", value: "\(report?.layout.extensionDescriptorDirectories.count ?? 0)")
                statItem(label: "本地包", value: "\(packages.count)")
            }
        }
        .padding(20)
        .background(
            LinearGradient(
                colors: [Color(red: 0.42, green: 0.36, blue: 0.91), Color(red: 0.64, green: 0.55, blue: 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.3), radius: 12, x: 0, y: 6)
    }

    private func statItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.white)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity)
    }

    private var quickActions: some View {
        HStack(spacing: 12) {
            actionButton(title: "导入壁纸", icon: "square.and.arrow.down.fill", color: Color(red: 0.2, green: 0.5, blue: 0.95)) {
                showImporter = true
            }
            actionButton(title: "视频转壁纸", icon: "video.fill.badge.plus", color: Color(red: 0.65, green: 0.35, blue: 0.95)) {
                showVideoImporter = true
            }
            actionButton(title: "刷新状态", icon: "arrow.clockwise", color: Color(red: 0.2, green: 0.65, blue: 0.45)) {
                checkAccess()
            }
        }
    }

    private func actionButton(title: String, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 22))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.91).opacity(0.5))
            Text("还没有壁纸包")
                .font(.headline)
            Text("点击上方按钮导入 .tendies 壁纸包，或把视频转换成动态壁纸")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var wallpaperGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本地壁纸库")
                .font(.headline)
                .foregroundStyle(.primary)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(packages) { pkg in
                    WallpaperGridCard(package: pkg) {
                        selectedPackage = pkg
                        showDetail = true
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if isBusy {
            ZStack {
                Color.black.opacity(0.15).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(language.text(operationKey))
                        .font(.subheadline.weight(.medium))
                }
                .padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func alertContent(_ alert: WallpaperLabAlert) -> Alert {
        switch alert.kind {
        case .install(let pkg):
            return Alert(
                title: Text("安装壁纸"),
                message: Text("确定安装「\(pkg.displayName)」？包含 \(pkg.payload.descriptors.count) 个描述符。"),
                primaryButton: .destructive(Text("安装")) { install(pkg) },
                secondaryButton: .cancel()
            )
        case .resetAll:
            return Alert(
                title: Text("重置全部自定义壁纸"),
                message: Text("这将删除所有已安装的自定义描述符，系统壁纸不受影响。"),
                primaryButton: .destructive(Text("重置")) { resetAll() },
                secondaryButton: .cancel()
            )
        case .message(let titleKey, let message):
            return Alert(title: Text(language.text(titleKey)), message: Text(message), dismissButton: .default(Text("好的")))
        default:
            return Alert(title: Text("操作"), dismissButton: .default(Text("好的")))
        }
    }

    private func checkAccess() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.checking"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try WallpaperDeviceAccessService.report() }
            DispatchQueue.main.async {
                isBusy = false
                if case .success(let r) = result { report = r }
            }
        }
    }

    private func importPackages(_ urls: [URL]) {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.importing"
        DispatchQueue.global(qos: .userInitiated).async {
            var count = 0
            for url in urls {
                if let _ = try? WallpaperPackageStore.importPackage(from: url) { count += 1 }
            }
            DispatchQueue.main.async {
                isBusy = false
                packages = WallpaperPackageStore.packages()
                alert = WallpaperLabAlert(kind: .message(titleKey: "wallpaper.import_done_title", message: "成功导入 \(count) 个壁纸包"))
            }
        }
    }

    private func convertVideo(_ url: URL) {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "Converting video..."
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> URL in
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("wlp-convert-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tendiesURL = try WallpaperVideoConverter.convert(videoURL: url, outputDirectory: tempDir)
                let pkg = try WallpaperPackageStore.importPackage(from: tendiesURL, displayName: url.deletingPathExtension().lastPathComponent)
                try? FileManager.default.removeItem(at: tempDir)
                return pkg.archiveURL
            }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success:
                    packages = WallpaperPackageStore.packages()
                    alert = WallpaperLabAlert(kind: .message(titleKey: "wallpaper.import_done_title", message: "视频转换成功，已导入壁纸库"))
                case .failure(let error):
                    alert = WallpaperLabAlert(kind: .message(titleKey: "wallpaper.operation_failed", message: error.localizedDescription))
                }
            }
        }
    }

    private func install(_ pkg: WallpaperStagedPackage) {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.installing"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try WallpaperDeviceAccessService.install(pkg) }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let (_, refreshed)):
                    report = refreshed
                    packages = WallpaperPackageStore.packages()
                    _ = openApplicationForBundleID("com.apple.PosterBoard")
                    alert = WallpaperLabAlert(kind: .message(titleKey: "wallpaper.install_done_title", message: "安装成功，请在壁纸设置中选择"))
                case .failure(let error):
                    alert = WallpaperLabAlert(kind: .message(titleKey: "wallpaper.operation_failed", message: error.localizedDescription))
                }
            }
        }
    }

    private func resetAll() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.restoring"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try WallpaperDeviceAccessService.resetCustomCollections() }
            DispatchQueue.main.async {
                isBusy = false
                if case .success(let (_, refreshed)) = result {
                    report = refreshed
                    alert = WallpaperLabAlert(kind: .message(titleKey: "wallpaper.reset_done_title", message: "已重置全部自定义壁纸"))
                }
            }
        }
    }
}

struct WallpaperGridCard: View {
    let package: WallpaperStagedPackage
    let action: () -> Void

    private var posterType: WallpaperPosterType? {
        package.payload.descriptors.compactMap { WallpaperPosterLayout.type(for: $0.extensionIdentifier) }.first
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [gradientColor.opacity(0.7), gradientColor.opacity(0.4)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 120)
                    Image(systemName: posterType?.systemImage ?? "photo.on.rectangle")
                        .font(.system(size: 32))
                        .foregroundStyle(.white)
                        .padding(14)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.displayName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text("\(package.payload.descriptors.count) 描述符 · \(sizeText(package.payload.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(12)
            }
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private var gradientColor: Color {
        switch posterType {
        case .photos: return Color(red: 0.65, green: 0.35, blue: 0.95)
        case .mercury: return Color(red: 0.95, green: 0.55, blue: 0.2)
        case .weather: return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .astronomy: return Color(red: 0.3, green: 0.2, blue: 0.6)
        default: return Color(red: 0.42, green: 0.36, blue: 0.91)
        }
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct WallpaperDetailView: View {
    let package: WallpaperStagedPackage
    let canInstall: Bool
    let onInstall: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                ZStack {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color(red: 0.42, green: 0.36, blue: 0.91), Color(red: 0.64, green: 0.55, blue: 0.96)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 180)
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 56))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(.horizontal, -16)

                VStack(alignment: .leading, spacing: 16) {
                    Text(package.displayName)
                        .font(.title2.weight(.bold))

                    HStack(spacing: 16) {
                        detailStat(label: "描述符", value: "\(package.payload.descriptors.count)")
                        detailStat(label: "大小", value: ByteCountFormatter.string(fromByteCount: package.payload.totalBytes, countStyle: .file))
                        detailStat(label: "文件", value: "\(package.payload.fileCount)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("描述符列表")
                            .font(.headline)
                        ForEach(package.payload.descriptors) { desc in
                            HStack {
                                Image(systemName: WallpaperPosterLayout.type(for: desc.extensionIdentifier)?.systemImage ?? "doc")
                                    .foregroundStyle(Color(red: 0.42, green: 0.36, blue: 0.91))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(desc.directoryURL.lastPathComponent)
                                        .font(.subheadline.weight(.medium))
                                    Text(desc.extensionIdentifier)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(desc.fileCount) 文件")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(Color(red: 0.96, green: 0.96, blue: 0.98))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Button(action: onInstall) {
                        Text("安装壁纸")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(canInstall ? Color(red: 0.42, green: 0.36, blue: 0.91) : Color.gray)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(!canInstall)
                }
                .padding(.horizontal, 16)
            }
        }
        .background(Color(red: 0.96, green: 0.96, blue: 0.98).ignoresSafeArea())
        .navigationTitle(package.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func detailStat(label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.headline.weight(.bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(red: 0.96, green: 0.96, blue: 0.98))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct InstalledWallpapersTabView: View {
    @State private var report: WallpaperAccessReport?
    @State private var isLoading = true
    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    var body: some View {
        InstalledWallpapersView(report: report)
            .onAppear(perform: load)
            .overlay {
                if isLoading {
                    ProgressView()
                }
            }
    }

    private func load() {
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try WallpaperDeviceAccessService.report() }
            DispatchQueue.main.async {
                isLoading = false
                if case .success(let r) = result { report = r }
            }
        }
    }
}

struct WallpaperSettingsView: View {
    @Environment(\.appLanguage) private var language
    @State private var report: WallpaperAccessReport?
    @State private var isBusy = false
    @State private var alert: WallpaperResetAlert?
    let onOpenLogs: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section("访问状态") {
                    if let report {
                        Label(report.canInstall ? "读写就绪" : "只读模式", systemImage: report.canInstall ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(report.canInstall ? Color.green : Color.orange)
                        LabeledContent("Generation", value: report.layout.generation)
                        LabeledContent("已安装描述符", value: "\(report.descriptorCount)")
                        LabeledContent("自定义描述符", value: "\(report.customDescriptorCount)")
                    } else {
                        ProgressView()
                    }
                }

                Section("操作") {
                    Button(role: .destructive) {
                        alert = WallpaperResetAlert(kind: .confirm)
                    } label: {
                        Label("重置全部自定义壁纸", systemImage: "arrow.counterclockwise")
                    }
                    .disabled(!(report?.canInstall ?? false) || isBusy)

                    Button {
                        onOpenLogs()
                    } label: {
                        Label("查看日志", systemImage: "doc.text")
                    }
                }

                Section("关于") {
                    LabeledContent("应用名称", value: "壁纸工坊")
                    LabeledContent("版本", value: "2.0")
                    LabeledContent("基于", value: "3105 内核")
                    LabeledContent("Bundle ID", value: "com.apple.mobile.MobileHouseArrest")
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.large)
            .tint(Color(red: 0.42, green: 0.36, blue: 0.91))
            .alert(item: $alert) { alert in
                switch alert.kind {
                case .confirm:
                    return Alert(
                        title: Text("重置全部自定义壁纸"),
                        message: Text("这将删除 \(report?.customDescriptorCount ?? 0) 个自定义描述符，不可撤销。"),
                        primaryButton: .destructive(Text("重置"), action: reset),
                        secondaryButton: .cancel()
                    )
                case .success:
                    return Alert(title: Text("已重置"), message: Text("全部自定义壁纸已清除"), dismissButton: .default(Text("好的")))
                case .failure(let msg):
                    return Alert(title: Text("失败"), message: Text(msg), dismissButton: .default(Text("好的")))
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try WallpaperDeviceAccessService.report() }
            DispatchQueue.main.async {
                isBusy = false
                if case .success(let r) = result { report = r }
            }
        }
    }

    private func reset() {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try WallpaperDeviceAccessService.resetCustomCollections() }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let (_, refreshed)):
                    report = refreshed
                    alert = WallpaperResetAlert(kind: .success)
                case .failure(let error):
                    alert = WallpaperResetAlert(kind: .failure(error.localizedDescription))
                }
            }
        }
    }
}

private struct WallpaperResetAlert: Identifiable {
    let id = UUID()
    let kind: Kind
    enum Kind {
        case confirm
        case success
        case failure(String)
    }
}

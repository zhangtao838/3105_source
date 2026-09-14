import SwiftUI
import UniformTypeIdentifiers
import AVFoundation

private enum WallpaperPickerPolicy {
    static let packageType = UTType(filenameExtension: "tendies") ?? .data
    static let videoTypes: [UTType] = [.movie, .mpeg4Movie, .quickTimeMovie, .video]
    static let allowedContentTypes: [UTType] = [packageType, .data]
}

struct WallpaperLabView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var report: WallpaperAccessReport?
    @State private var accessError: String?
    @State private var packages: [WallpaperStagedPackage] = []
    @State private var isBusy = false
    @State private var operationKey = "wallpaper.checking"
    @State private var showImporter = false
    @State private var showVideoImporter = false
    @State private var showInstalled = false
    @State private var alert: WallpaperLabAlert?
    @State private var hasLoaded = false
    @State private var editMode: EditMode = .inactive
    @State private var selectedPackages = Set<UUID>()
    @State private var showSimulatedPackageDetail = false

    let onOpenSettings: () -> Void
    let onOpenLogs: () -> Void

    init(
        onOpenSettings: @escaping () -> Void = {},
        onOpenLogs: @escaping () -> Void = {}
    ) {
        self.onOpenSettings = onOpenSettings
        self.onOpenLogs = onOpenLogs
    }

    var body: some View {
        NavigationStack {
            List {
                accessSection
                quickActionsSection
                packagesSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(language.text("wallpaper.title"))
            .navigationBarTitleDisplayMode(.inline)
            .environment(\.editMode, $editMode)
            .toolbar { toolbarContent }
            .overlay { busyOverlay }
            .alert(item: $alert, content: alertContent)
            .sheet(isPresented: $showImporter) {
                FileDocumentPicker(
                    allowedContentTypes: WallpaperPickerPolicy.allowedContentTypes,
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
                    allowedContentTypes: WallpaperPickerPolicy.videoTypes,
                    copiesSelectedDocument: true,
                    allowsMultipleSelection: false,
                    onSelection: { result in
                        showVideoImporter = false
                        if case .success(let urls) = result, let url = urls.first {
                            convertVideoToWallpaper(url)
                        }
                    },
                    onCancel: { showVideoImporter = false }
                )
                .ignoresSafeArea()
            }
            .navigationDestination(isPresented: $showInstalled) {
                InstalledWallpapersView(report: report)
            }
            .navigationDestination(isPresented: $showSimulatedPackageDetail) {
                if let package = packages.first {
                    WallpaperPackageDetailView(
                        package: package,
                        canInstall: report?.canInstall == true && !isBusy,
                        onApply: {
                            alert = WallpaperLabAlert(kind: .install(package))
                        }
                    )
                }
            }
            .onAppear {
                guard !hasLoaded else { return }
                hasLoaded = true
                reloadLocalData()
                checkAccess()
#if targetEnvironment(simulator)
                if ProcessInfo.processInfo.arguments.contains(
                    "--simulate-wallpaper-detail"
                ), !packages.isEmpty {
                    DispatchQueue.main.async {
                        showSimulatedPackageDetail = true
                    }
                }
#endif
            }
        }
    }

    private var accessSection: some View {
        Section {
            if let report {
                HStack {
                    Label(
                        language.text(report.canInstall
                            ? "wallpaper.access_ready"
                            : "wallpaper.access_read_only"),
                        systemImage: report.canInstall
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(report.canInstall ? Color.green : Color.orange)
                    Spacer()
                    Text("MHA-C2")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 12) {
                    LabeledContent("Gen") {
                        Text(report.layout.generation).monospacedDigit()
                    }
                    LabeledContent("Types") {
                        Text("\(report.layout.extensionDescriptorDirectories.count)").monospacedDigit()
                    }
                    LabeledContent("Total") {
                        Text("\(report.descriptorCount)").monospacedDigit()
                    }
                    LabeledContent("Custom") {
                        Text("\(report.customDescriptorCount)").monospacedDigit()
                    }
                }
                .font(.caption)
                if !report.layout.supportedTypes.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(report.layout.supportedTypes, id: \.self) { type in
                                Label(type.displayName, systemImage: type.systemImage)
                                    .font(.caption2)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                            }
                        }
                    }
                }
            } else if let accessError {
                Label(accessError, systemImage: "xmark.shield.fill")
                    .foregroundStyle(.red)
                Button(language.text("wallpaper.try_again")) { checkAccess() }
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(language.text("wallpaper.checking"))
                }
            }
        } header: { Text(language.text("wallpaper.access")) }
    }

    private var quickActionsSection: some View {
        Section {
            HStack(spacing: 12) {
                QuickActionButton(
                    title: "Import",
                    systemImage: "square.and.arrow.down.fill",
                    color: .blue
                ) { showImporter = true }
                QuickActionButton(
                    title: "Video→WP",
                    systemImage: "video.fill.badge.plus",
                    color: .purple
                ) { showVideoImporter = true }
                QuickActionButton(
                    title: "Installed",
                    systemImage: "checkmark.circle.fill",
                    color: .green
                ) { showInstalled = true }
                QuickActionButton(
                    title: editMode == .active ? "Done" : "Select",
                    systemImage: editMode == .active ? "checkmark.circle.fill" : "checklist",
                    color: editMode == .active ? .orange : .gray
                ) {
                    withAnimation {
                        editMode = editMode == .active ? .inactive : .active
                        if editMode == .inactive { selectedPackages.removeAll() }
                    }
                }
            }
            .padding(.vertical, 4)
            if editMode == .active && !selectedPackages.isEmpty {
                HStack(spacing: 12) {
                    Button {
                        alert = WallpaperLabAlert(kind: .batchInstall(Array(selectedPackages)))
                    } label: {
                        Label("Install All", systemImage: "square.and.arrow.down.fill")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                    .disabled(!(report?.canInstall ?? false) || isBusy)

                    Button(role: .destructive) {
                        alert = WallpaperLabAlert(kind: .batchDelete(Array(selectedPackages)))
                    } label: {
                        Label("Delete All", systemImage: "trash.fill")
                            .frame(maxWidth: .infinity, minHeight: 40)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(isBusy)
                }
            }
        } header: { Text("Quick Actions") }
    }

    private var packagesSection: some View {
        Section {
            if packages.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.badge.plus")
                        .font(.system(size: AppTheme.emptyIconSize, weight: .light))
                        .foregroundStyle(AppTheme.accent)
                    Text(language.text("wallpaper.empty_packages"))
                        .font(.headline)
                    Text(language.text("wallpaper.empty_packages_message"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(packages) { package in
                    if editMode == .active {
                        packageCard(package)
                            .overlay(alignment: .topLeading) {
                                Image(systemName: selectedPackages.contains(package.id)
                                    ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedPackages.contains(package.id)
                                        ? Color.accentColor : Color.gray)
                                    .padding(8)
                            }
                            .onTapGesture {
                                if selectedPackages.contains(package.id) {
                                    selectedPackages.remove(package.id)
                                } else {
                                    selectedPackages.insert(package.id)
                                }
                            }
                    } else {
                        NavigationLink {
                            WallpaperPackageDetailView(
                                package: package,
                                canInstall: report?.canInstall == true && !isBusy,
                                onApply: {
                                    alert = WallpaperLabAlert(kind: .install(package))
                                }
                            )
                        } label: {
                            packageCard(package)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                deletePackage(package)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                            }
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                alert = WallpaperLabAlert(kind: .install(package))
                            } label: {
                                Label("Install", systemImage: "square.and.arrow.down.fill")
                            }
                            .tint(.green)
                            .disabled(!(report?.canInstall ?? false) || isBusy)
                        }
                    }
                }
            }
        } header: {
            HStack {
                Text(language.text("wallpaper.packages"))
                Spacer()
                if !packages.isEmpty {
                    Text("\(packages.count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(language.text("wallpaper.after_apply_guide"))
        }
    }

    private func packageCard(_ package: WallpaperStagedPackage) -> some View {
        let types = Set(package.payload.descriptors.compactMap {
            WallpaperPosterLayout.type(for: $0.extensionIdentifier)
        })
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay {
                        Image(systemName: types.first?.systemImage ?? "photo.on.rectangle.angled")
                            .font(.title2)
                            .foregroundStyle(Color.accentColor)
                    }
                VStack(alignment: .leading, spacing: 3) {
                    Text(package.displayName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(
                        "\(package.payload.descriptors.count) descriptors · \(sizeText(package.payload.totalBytes)) · \(package.payload.fileCount) files"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
            }
            if !types.isEmpty {
                HStack(spacing: 6) {
                    ForEach(Array(types), id: \.self) { type in
                        Label(type.displayName, systemImage: type.systemImage)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.accentColor.opacity(0.1), in: Capsule())
                    }
                    Spacer()
                    Text(package.importedAt, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            Button { checkAccess() } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(isBusy)
            .accessibilityLabel(language.text("wallpaper.try_again"))
        }
        ToolbarItem(placement: .navigationBarTrailing) {
            Menu {
                Button {
                    showImporter = true
                } label: {
                    Label("Import .tendies", systemImage: "square.and.arrow.down")
                }
                Button {
                    showVideoImporter = true
                } label: {
                    Label("Convert Video", systemImage: "video.fill.badge.plus")
                }
                Button {
                    showInstalled = true
                } label: {
                    Label("View Installed", systemImage: "checkmark.circle")
                }
                Divider()
                Button(role: .destructive) {
                    alert = WallpaperLabAlert(kind: .resetAll)
                } label: {
                    Label("Reset All Custom", systemImage: "arrow.counterclockwise")
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

    @ViewBuilder
    private var busyOverlay: some View {
        if isBusy {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(language.text(operationKey))
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private func alertContent(_ alert: WallpaperLabAlert) -> Alert {
        switch alert.kind {
        case .install(let package):
            return Alert(
                title: Text(language.text("wallpaper.install_warning_title")),
                message: Text(
                    language.text(
                        "wallpaper.install_warning_message",
                        package.displayName,
                        Int64(package.payload.descriptors.count),
                        AppInfo.osVersion,
                        AppInfo.osBuild
                    )
                ),
                primaryButton: .destructive(Text(language.text("wallpaper.install"))) {
                    install(package)
                },
                secondaryButton: .cancel(Text(language.text("common.cancel")))
            )
        case .batchInstall(let ids):
            return Alert(
                title: Text("Install \(ids.count) Wallpapers?"),
                message: Text("This will install all selected wallpaper packages to PosterBoard."),
                primaryButton: .default(Text("Install All")) {
                    batchInstall(ids)
                },
                secondaryButton: .cancel()
            )
        case .batchDelete(let ids):
            return Alert(
                title: Text("Delete \(ids.count) Packages?"),
                message: Text("This will remove the selected packages from staging. Installed wallpapers are not affected."),
                primaryButton: .destructive(Text("Delete All")) {
                    batchDelete(ids)
                },
                secondaryButton: .cancel()
            )
        case .resetAll:
            return Alert(
                title: Text("Reset All Custom Wallpapers?"),
                message: Text("This will remove all custom descriptors installed by 3105. System wallpapers are not affected."),
                primaryButton: .destructive(Text("Reset")) {
                    resetAll()
                },
                secondaryButton: .cancel()
            )
        case .message(let titleKey, let message):
            return Alert(
                title: Text(language.text(titleKey)),
                message: Text(message),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

    private func reloadLocalData() {
        packages = WallpaperPackageStore.packages()
    }

    private func checkAccess() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.checking"
        accessError = nil
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { try deviceAccessReport() }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let newReport):
                    report = newReport
                    log(
                        "wallpaper: probe generation=\(newReport.layout.generation) " +
                            "extensions=\(newReport.layout.extensionDescriptorDirectories.count) " +
                            "writable=\(newReport.canInstall)"
                    )
                case .failure(let error):
                    report = nil
                    accessError = message(for: error)
                    log("wallpaper: probe failed \(error.localizedDescription)")
                }
            }
        }
    }

    private func importPackages(_ urls: [URL]) {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.importing"
        DispatchQueue.global(qos: .userInitiated).async {
            var imported = 0
            var failures: [String] = []
            for url in urls {
                do {
                    _ = try WallpaperPackageStore.importPackage(from: url)
                    imported += 1
                    log("wallpaper: staged \(url.lastPathComponent)")
                } catch {
                    failures.append("\(url.lastPathComponent): \(message(for: error))")
                    log("wallpaper: import rejected \(url.lastPathComponent)")
                }
            }
            DispatchQueue.main.async {
                isBusy = false
                reloadLocalData()
                alert = WallpaperLabAlert(
                    kind: .message(
                        titleKey: failures.isEmpty
                            ? "wallpaper.import_done_title" : "wallpaper.import_result_title",
                        message: failures.isEmpty
                            ? language.text("wallpaper.import_done_message", Int64(imported))
                            : failures.joined(separator: "\n")
                    )
                )
            }
        }
    }

    private func convertVideoToWallpaper(_ videoURL: URL) {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "Converting video..."
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> URL in
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("3105-video-convert-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tendiesURL = try WallpaperVideoConverter.convert(
                    videoURL: videoURL,
                    outputDirectory: tempDir
                )
                let package = try WallpaperPackageStore.importPackage(
                    from: tendiesURL,
                    displayName: videoURL.deletingPathExtension().lastPathComponent
                )
                try? FileManager.default.removeItem(at: tempDir)
                return package.archiveURL
            }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success:
                    reloadLocalData()
                    alert = WallpaperLabAlert(
                        kind: .message(
                            titleKey: "wallpaper.import_done_title",
                            message: "Video converted and imported successfully."
                        )
                    )
                case .failure(let error):
                    alert = WallpaperLabAlert(
                        kind: .message(
                            titleKey: "wallpaper.operation_failed",
                            message: error.localizedDescription
                        )
                    )
                }
            }
        }
    }

    private func install(_ package: WallpaperStagedPackage) {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.installing"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result { () throws -> (WallpaperInstallReceipt, WallpaperAccessReport) in
                let requiredExtensions = Set(
                    package.payload.descriptors.map(\.extensionIdentifier)
                )
                let currentReport = try deviceAccessReport(
                    requiredExtensionIdentifiers: requiredExtensions
                )
                guard currentReport.canInstall else { throw WallpaperLabError.accessDenied }
                let backupRoot = try WallpaperPackageStore.backupRoot()
                let receipt = try WallpaperInstaller.install(
                    payload: package.payload,
                    layout: currentReport.layout,
                    backupRoot: backupRoot
                )
                do {
                    try WallpaperPackageStore.delete(package)
                } catch {
                    log("wallpaper: staged package leftover after apply")
                }
                let refreshedReport = try deviceAccessReport(
                    requiredExtensionIdentifiers: requiredExtensions
                )
                return (receipt, refreshedReport)
            }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let (receipt, refreshedReport)):
                    reloadLocalData()
                    report = refreshedReport
                    log("wallpaper: installed descriptors=\(receipt.installedDescriptors.count)")
                    let opened = openApplicationForBundleID("com.apple.PosterBoard")
                    alert = WallpaperLabAlert(
                        kind: .message(
                            titleKey: "wallpaper.install_done_title",
                            message: language.text(
                                opened
                                    ? "wallpaper.install_done_opened"
                                    : "wallpaper.install_done_manual"
                            )
                        )
                    )
                case .failure(let error):
                    log("wallpaper: install failed \(error.localizedDescription)")
                    alert = WallpaperLabAlert(
                        kind: .message(
                            titleKey: "wallpaper.operation_failed",
                            message: message(for: error)
                        )
                    )
                }
            }
        }
    }

    private func batchInstall(_ ids: [UUID]) {
        guard !isBusy else { return }
        let targetPackages = packages.filter { ids.contains($0.id) }
        guard !targetPackages.isEmpty else { return }
        isBusy = true
        operationKey = "Installing \(targetPackages.count) wallpapers..."
        DispatchQueue.global(qos: .userInitiated).async {
            var success = 0
            var failures: [String] = []
            for package in targetPackages {
                do {
                    _ = try WallpaperDeviceAccessService.install(package)
                    success += 1
                } catch {
                    failures.append("\(package.displayName): \(error.localizedDescription)")
                }
            }
            DispatchQueue.main.async {
                isBusy = false
                reloadLocalData()
                checkAccess()
                editMode = .inactive
                selectedPackages.removeAll()
                alert = WallpaperLabAlert(
                    kind: .message(
                        titleKey: "wallpaper.import_done_title",
                        message: "Installed \(success)/\(targetPackages.count) wallpapers." +
                            (failures.isEmpty ? "" : "\n\nFailures:\n\(failures.joined(separator: "\n"))")
                    )
                )
            }
        }
    }

    private func deletePackage(_ package: WallpaperStagedPackage) {
        do {
            try WallpaperPackageStore.delete(package)
            reloadLocalData()
        } catch {
            alert = WallpaperLabAlert(
                kind: .message(
                    titleKey: "wallpaper.operation_failed",
                    message: message(for: error)
                )
            )
        }
    }

    private func batchDelete(_ ids: [UUID]) {
        for package in packages where ids.contains(package.id) {
            try? WallpaperPackageStore.delete(package)
        }
        reloadLocalData()
        editMode = .inactive
        selectedPackages.removeAll()
    }

    private func resetAll() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.restoring"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try WallpaperDeviceAccessService.resetCustomCollections()
            }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let (removed, refreshedReport)):
                    report = refreshedReport
                    log("wallpaper: reset removed \(removed) custom descriptors")
                    _ = openApplicationForBundleID("com.apple.PosterBoard")
                    alert = WallpaperLabAlert(
                        kind: .message(
                            titleKey: "wallpaper.reset_done_title",
                            message: language.text("wallpaper.reset_done_message")
                        )
                    )
                case .failure(let error):
                    alert = WallpaperLabAlert(
                        kind: .message(
                            titleKey: "wallpaper.operation_failed",
                            message: message(for: error)
                        )
                    )
                }
            }
        }
    }

    private func deviceAccessReport(
        requiredExtensionIdentifiers: Set<String>? = nil
    ) throws -> WallpaperAccessReport {
#if targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--simulate-wallpaper-data") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(
                "3105-Simulated-PosterBoard",
                isDirectory: true
            )
            let descriptors = root.appendingPathComponent(
                "Library/Application Support/PRBPosterExtensionDataStore/72/Extensions/" +
                    "com.apple.WallpaperKit.CollectionsPoster/descriptors",
                isDirectory: true
            )
            try FileManager.default.createDirectory(at: descriptors, withIntermediateDirectories: true)
            return try WallpaperAccessProbe.probe(
                containerURL: root,
                rootValidator: { $0.standardizedFileURL == root.standardizedFileURL },
                requiredExtensionIdentifiers: requiredExtensionIdentifiers
            )
        }
#endif
        guard let path = ContainerStore.resolveAppContainerPath(
            bundleID: "com.apple.PosterBoard"
        ) else { throw WallpaperLabError.accessDenied }
        return try WallpaperAccessProbe.probe(
            containerURL: URL(fileURLWithPath: path, isDirectory: true),
            rootValidator: { ContainerStore.isApplicationContainerPath($0.path) },
            requiredExtensionIdentifiers: requiredExtensionIdentifiers
        )
    }

    private func message(for error: Error) -> String {
        if let wallpaperError = error as? WallpaperLabError {
            return language.text(wallpaperError.localizationKey)
        }
        return language.text("wallpaper.error.unknown")
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct QuickActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
}

private struct WallpaperPackageDetailView: View {
    @Environment(\.appLanguage) private var language
    let package: WallpaperStagedPackage
    let canInstall: Bool
    let onApply: () -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.accentColor.opacity(0.1))
                        .frame(width: 64, height: 64)
                        .overlay {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title)
                                .foregroundStyle(Color.accentColor)
                        }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(package.displayName)
                            .font(.title3.weight(.bold))
                        Text("\(package.payload.descriptors.count) descriptors")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text("\(sizeText(package.payload.totalBytes)) · \(package.payload.fileCount) files")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Descriptors") {
                ForEach(package.payload.descriptors) { descriptor in
                    let type = WallpaperPosterLayout.type(for: descriptor.extensionIdentifier)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            if let type {
                                Label(type.displayName, systemImage: type.systemImage)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                            }
                            Spacer()
                            Text("\(descriptor.fileCount) files · \(sizeText(descriptor.byteCount))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(descriptor.directoryURL.lastPathComponent)
                            .font(.body.weight(.semibold))
                        Text(descriptor.extensionIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    .padding(.vertical, 3)
                }
            }

            Section {
                Button(action: onApply) {
                    Text(language.text("wallpaper.install"))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canInstall)
            } footer: {
                Text(language.text("wallpaper.after_apply_guide"))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(package.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

struct InstalledWallpapersView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    let report: WallpaperAccessReport?
    @State private var installedItems: [InstalledWallpaperItem] = []
    @State private var isLoading = true
    @State private var isBusy = false
    @State private var alert: InstalledAlert?

    var body: some View {
        List {
            if isLoading {
                HStack {
                    ProgressView()
                    Text("Scanning PosterBoard...")
                }
            } else if installedItems.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "photo.stack")
                        .font(.system(size: 40, weight: .light))
                        .foregroundStyle(.secondary)
                    Text("No Custom Wallpapers")
                        .font(.headline)
                    Text("Installed custom wallpapers will appear here.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
            } else {
                ForEach(installedItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if let type = item.type {
                                Label(type.displayName, systemImage: type.systemImage)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.accentColor.opacity(0.1), in: Capsule())
                            }
                            Spacer()
                            Text(sizeText(item.byteCount))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Text(item.directoryName)
                            .font(.body.weight(.semibold))
                            .lineLimit(1)
                        Text(item.extensionIdentifier)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        HStack {
                            Button {
                                exportItem(item)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.blue)

                            Button(role: .destructive) {
                                alert = .confirmDelete(item)
                            } label: {
                                Label("Delete", systemImage: "trash.fill")
                                    .font(.caption)
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .disabled(isBusy)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Installed Wallpapers")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isBusy {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView()
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .alert(item: $alert) { alert in
            switch alert {
            case .confirmDelete(let item):
                return Alert(
                    title: Text("Delete Wallpaper?"),
                    message: Text("This will remove '\(item.directoryName)' from PosterBoard. This cannot be undone."),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteItem(item)
                    },
                    secondaryButton: .cancel()
                )
            case .message(let title, let message):
                return Alert(
                    title: Text(title),
                    message: Text(message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
        .onAppear(perform: scanInstalled)
    }

    private func scanInstalled() {
        guard let report else {
            isLoading = false
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            var items: [InstalledWallpaperItem] = []
            let fm = FileManager.default
            for (identifier, directoryURL) in report.layout.extensionDescriptorDirectories {
                guard let children = try? fm.contentsOfDirectory(
                    at: directoryURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .totalFileSizeKey]
                ) else { continue }
                for child in children {
                    let name = child.lastPathComponent
                    if name.hasPrefix(".") { continue }
                    let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                    guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                    guard WallpaperDescriptorIdentity.isCustom(at: child) else { continue }
                    var size: Int64 = 0
                    if let enumerator = fm.enumerator(at: child, includingPropertiesForKeys: [.fileSizeKey]) {
                        for case let fileURL as URL in enumerator {
                            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                                size += Int64(fileSize)
                            }
                        }
                    }
                    items.append(InstalledWallpaperItem(
                        directoryName: name,
                        extensionIdentifier: identifier,
                        url: child,
                        byteCount: size,
                        type: WallpaperPosterLayout.type(for: identifier)
                    ))
                }
            }
            DispatchQueue.main.async {
                installedItems = items.sorted { $0.directoryName < $1.directoryName }
                isLoading = false
            }
        }
    }

    private func exportItem(_ item: InstalledWallpaperItem) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("3105-export-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                let descriptorsDir = tempDir.appendingPathComponent("descriptors", isDirectory: true)
                try FileManager.default.createDirectory(at: descriptorsDir, withIntermediateDirectories: true)
                let destURL = descriptorsDir.appendingPathComponent(item.directoryName)
                try FileManager.default.copyItem(at: item.url, to: destURL)

                let tendiesURL = tempDir.appendingPathComponent("\(item.directoryName).tendies")
                let coordinator = NSFileCoordinator()
                var error: NSError?
                coordinator.coordinate(readingItemAt: descriptorsDir, options: .forUploading, error: &error) { zipURL in
                    try? FileManager.default.removeItem(at: tendiesURL)
                    try? FileManager.default.copyItem(at: zipURL, to: tendiesURL)
                }

                let docsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let finalURL = docsURL.appendingPathComponent("\(item.directoryName).tendies")
                try? FileManager.default.removeItem(at: finalURL)
                try FileManager.default.copyItem(at: tendiesURL, to: finalURL)
                try? FileManager.default.removeItem(at: tempDir)

                DispatchQueue.main.async {
                    isBusy = false
                    alert = .message("Exported", "Saved to Documents: \(item.directoryName).tendies")
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    alert = .message("Export Failed", error.localizedDescription)
                }
            }
        }
    }

    private func deleteItem(_ item: InstalledWallpaperItem) {
        isBusy = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try FileManager.default.removeItem(at: item.url)
                DispatchQueue.main.async {
                    isBusy = false
                    installedItems.removeAll { $0.id == item.id }
                    alert = .message("Deleted", "Wallpaper removed successfully.")
                }
            } catch {
                DispatchQueue.main.async {
                    isBusy = false
                    alert = .message("Delete Failed", error.localizedDescription)
                }
            }
        }
    }

    private func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct InstalledWallpaperItem: Identifiable, Equatable {
    let directoryName: String
    let extensionIdentifier: String
    let url: URL
    let byteCount: Int64
    let type: WallpaperPosterType?

    var id: String { "\(extensionIdentifier):\(directoryName)" }
}

private enum InstalledAlert: Identifiable {
    case confirmDelete(InstalledWallpaperItem)
    case message(String, String)

    var id: String {
        switch self {
        case .confirmDelete(let item): return "delete-\(item.id)"
        case .message(let title, _): return "msg-\(title)"
        }
    }
}

struct InstalledWallpaperPackageDetailView: View {
    @Environment(\.appLanguage) private var language
    @Environment(\.dismiss) private var dismiss
    @State private var report: WallpaperAccessReport?
    @State private var isBusy = true
    @State private var operationKey = "wallpaper.checking"
    @State private var alert: InstalledWallpaperAlert?

    let package: WallpaperStagedPackage
    let onApplied: () -> Void

    var body: some View {
        WallpaperPackageDetailView(
            package: package,
            canInstall: report?.canInstall == true && !isBusy,
            onApply: {
                alert = InstalledWallpaperAlert(kind: .confirmInstall)
            }
        )
        .overlay { busyOverlay }
        .alert(item: $alert, content: alertContent)
        .onAppear(perform: checkAccess)
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if isBusy {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(language.text(operationKey))
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
    }

    private func alertContent(_ alert: InstalledWallpaperAlert) -> Alert {
        switch alert.kind {
        case .confirmInstall:
            return Alert(
                title: Text(language.text("wallpaper.install_warning_title")),
                message: Text(language.text(
                    "wallpaper.install_warning_message",
                    package.displayName,
                    Int64(package.payload.descriptors.count),
                    AppInfo.osVersion,
                    AppInfo.osBuild
                )),
                primaryButton: .destructive(
                    Text(language.text("wallpaper.install")),
                    action: install
                ),
                secondaryButton: .cancel(Text(language.text("common.cancel")))
            )
        case .success(let openedPosterBoard):
            return Alert(
                title: Text(language.text("wallpaper.install_done_title")),
                message: Text(language.text(
                    openedPosterBoard
                        ? "wallpaper.install_done_opened"
                        : "wallpaper.install_done_manual"
                )),
                dismissButton: .default(Text(language.text("common.ok"))) {
                    dismiss()
                }
            )
        case .failure(let message):
            return Alert(
                title: Text(language.text("wallpaper.operation_failed")),
                message: Text(message),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

    private func checkAccess() {
        guard isBusy else { return }
        operationKey = "wallpaper.checking"
        DispatchQueue.global(qos: .userInitiated).async {
            let requiredExtensions = Set(
                package.payload.descriptors.map(\.extensionIdentifier)
            )
            let result = Result {
                try WallpaperDeviceAccessService.report(
                    requiredExtensionIdentifiers: requiredExtensions
                )
            }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let newReport):
                    report = newReport
                case .failure(let error):
                    report = nil
                    alert = InstalledWallpaperAlert(
                        kind: .failure(message(for: error))
                    )
                }
            }
        }
    }

    private func install() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.installing"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try WallpaperDeviceAccessService.install(package)
            }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let (receipt, refreshedReport)):
                    report = refreshedReport
                    onApplied()
                    log(
                        "wallpaper: installed descriptors=" +
                            "\(receipt.installedDescriptors.count)"
                    )
                    let opened = openApplicationForBundleID("com.apple.PosterBoard")
                    alert = InstalledWallpaperAlert(kind: .success(opened))
                case .failure(let error):
                    log("wallpaper: install failed \(error.localizedDescription)")
                    alert = InstalledWallpaperAlert(
                        kind: .failure(message(for: error))
                    )
                }
            }
        }
    }

    private func message(for error: Error) -> String {
        if let wallpaperError = error as? WallpaperLabError {
            return language.text(wallpaperError.localizationKey)
        }
        return language.text("wallpaper.error.unknown")
    }
}

private struct InstalledWallpaperAlert: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case confirmInstall
        case success(Bool)
        case failure(String)
    }
}

struct WallpaperResetSettingsView: View {
    @Environment(\.appLanguage) private var language
    @State private var report: WallpaperAccessReport?
    @State private var isBusy = false
    @State private var operationKey = "wallpaper.checking"
    @State private var alert: WallpaperResetAlert?

    var body: some View {
        List {
            Section(language.text("wallpaper.access")) {
                if let report {
                    Label(
                        language.text(
                            report.canInstall
                                ? "wallpaper.access_ready"
                                : "wallpaper.access_read_only"
                        ),
                        systemImage: report.canInstall
                            ? "checkmark.shield.fill"
                            : "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(report.canInstall ? Color.green : Color.orange)
                    LabeledContent(language.text("wallpaper.custom_count")) {
                        Text("\(report.customDescriptorCount)")
                            .monospacedDigit()
                    }
                } else if !isBusy {
                    Label(
                        language.text("wallpaper.error.access"),
                        systemImage: "xmark.shield.fill"
                    )
                    .foregroundStyle(.red)
                }
            }

            if let report, report.customDescriptorCount > 0 {
                Section {
                    Button(role: .destructive) {
                        alert = WallpaperResetAlert(kind: .confirm)
                    } label: {
                        Label(
                            language.text("wallpaper.reset"),
                            systemImage: "arrow.counterclockwise"
                        )
                    }
                    .disabled(isBusy || !report.canInstall)
                } footer: {
                    Text(language.text("wallpaper.reset_footer"))
                }
            } else if report != nil {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.stack")
                            .font(.system(
                                size: AppTheme.emptyIconSize,
                                weight: .light
                            ))
                            .foregroundStyle(AppTheme.accent)
                        Text(language.text("wallpaper.no_custom_title"))
                            .font(.headline)
                        Text(language.text("wallpaper.no_custom_message"))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 28)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(language.text("wallpaper.reset"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: checkAccess) {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isBusy)
                .accessibilityLabel(language.text("wallpaper.try_again"))
            }
        }
        .overlay { busyOverlay }
        .alert(item: $alert, content: alertContent)
        .onAppear(perform: checkAccess)
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if isBusy {
            ZStack {
                Color.black.opacity(0.12).ignoresSafeArea()
                VStack(spacing: 12) {
                    ProgressView()
                    Text(language.text(operationKey))
                        .font(.subheadline.weight(.medium))
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 18)
                .background(
                    .regularMaterial,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
            }
        }
    }

    private func alertContent(_ alert: WallpaperResetAlert) -> Alert {
        switch alert.kind {
        case .confirm:
            return Alert(
                title: Text(language.text("wallpaper.reset_title")),
                message: Text(language.text(
                    "wallpaper.reset_message",
                    Int64(report?.customDescriptorCount ?? 0)
                )),
                primaryButton: .destructive(
                    Text(language.text("wallpaper.reset")),
                    action: resetCollections
                ),
                secondaryButton: .cancel(Text(language.text("common.cancel")))
            )
        case .success:
            return Alert(
                title: Text(language.text("wallpaper.reset_done_title")),
                message: Text(language.text("wallpaper.reset_done_message")),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        case .failure(let message):
            return Alert(
                title: Text(language.text("wallpaper.operation_failed")),
                message: Text(message),
                dismissButton: .default(Text(language.text("common.ok")))
            )
        }
    }

    private func checkAccess() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.checking"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try WallpaperDeviceAccessService.report()
            }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let newReport):
                    report = newReport
                case .failure(let error):
                    report = nil
                    alert = WallpaperResetAlert(
                        kind: .failure(message(for: error))
                    )
                }
            }
        }
    }

    private func resetCollections() {
        guard !isBusy else { return }
        isBusy = true
        operationKey = "wallpaper.restoring"
        DispatchQueue.global(qos: .userInitiated).async {
            let result = Result {
                try WallpaperDeviceAccessService.resetCustomCollections()
            }
            DispatchQueue.main.async {
                isBusy = false
                switch result {
                case .success(let (removed, refreshedReport)):
                    report = refreshedReport
                    log("wallpaper: reset removed \(removed) custom descriptors")
                    _ = openApplicationForBundleID("com.apple.PosterBoard")
                    alert = WallpaperResetAlert(kind: .success)
                case .failure(let error):
                    alert = WallpaperResetAlert(
                        kind: .failure(message(for: error))
                    )
                }
            }
        }
    }

    private func message(for error: Error) -> String {
        if let wallpaperError = error as? WallpaperLabError {
            return language.text(wallpaperError.localizationKey)
        }
        return language.text("wallpaper.error.unknown")
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

private struct WallpaperLabAlert: Identifiable {
    let id = UUID()
    let kind: Kind

    enum Kind {
        case install(WallpaperStagedPackage)
        case batchInstall([UUID])
        case batchDelete([UUID])
        case resetAll
        case message(titleKey: String, message: String)
    }
}

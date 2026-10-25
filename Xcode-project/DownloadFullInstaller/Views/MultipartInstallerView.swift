import SwiftUI
import UniformTypeIdentifiers

@MainActor
private final class MultipartAssemblyState: ObservableObject {
    static let shared = MultipartAssemblyState()
    @Published var activeFolders = Set<String>()
}

struct MultipartInstallerView: View {
    @ObservedObject var product: Product
    @ObservedObject private var manager = MultiDownloadManager.shared
    @ObservedObject private var assemblyState = MultipartAssemblyState.shared
    @State private var activeAlert: AppAlertType?
    @State private var replacement: Package?
    @State private var downloaded = Set<String>()

    private var isCreating: Bool {
        assemblyState.activeFolders.contains(Prefs.downloadURL.appendingPathComponent(product.componentFolder).path)
    }

    private var sizes: [String: Int] {
        Dictionary(uniqueKeysWithValues: product.installerComponents.compactMap { package in
            guard let name = URL(string: package.url)?.lastPathComponent else { return nil }
            return (name, package.size)
        })
    }

    private func filename(for package: Package) -> String {
        "\(product.componentFolder)/\(URL(string: package.url)?.lastPathComponent ?? "")"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                IconView(product: product)
                VStack(alignment: .leading) {
                    Text(product.title ?? product.osName ?? "")
                        .font(.title3.weight(.semibold))
                    Text("\(product.productVersion ?? "") · \(product.buildVersion ?? "")")
                    Text(product.postDate, style: .date)
                        .foregroundStyle(.secondary)
                }
            }
            Text(NSLocalizedString("Download all six components below. Open BaseSystem.dmg, then choose Create Installer App and select the installer app on that mounted image. Assembly requires additional free space equal to the downloaded components. These Intel installers cannot install macOS on Apple Silicon.", comment: "Multipart installer instructions"))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(product.componentFolder)
                .font(.caption.monospaced())
                .textSelection(.enabled)

            ForEach(product.installerComponents, id: \.url) { package in
                HStack {
                    if downloaded.contains(filename(for: package)) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel(NSLocalizedString("This installer has been downloaded", comment: ""))
                    }
                    Text(URL(string: package.url)?.lastPathComponent ?? "")
                        .font(.callout.monospaced())
                    Spacer()
                    Text(Prefs.byteFormatter.string(fromByteCount: Int64(package.size)))
                        .foregroundStyle(.secondary)
                    Button(NSLocalizedString("Download", comment: "Download component")) {
                        download(package)
                    }
                    .disabled(isCreating || manager.isDownloading(filename: filename(for: package)))
                }
                .contextMenu {
                    Button(NSLocalizedString("Copy Download URL", comment: "")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(package.url, forType: .string)
                    }
                }
            }

            if product.installerComponents.count != LegacyInstallerAssembler.componentNames.count {
                Text(NSLocalizedString("This catalog does not provide all six required installer components. Try the Regular catalog.", comment: "Incomplete multipart catalog entry"))
                    .foregroundStyle(.secondary)
            }
            HStack {
                Button(NSLocalizedString("Open BaseSystem Image", comment: "Mount legacy base image")) {
                    openBaseSystem()
                }
                .disabled(isCreating || !downloaded.contains("\(product.componentFolder)/BaseSystem.dmg"))
                Button(NSLocalizedString("Create Installer App", comment: "")) {
                    createInstaller()
                }
                .disabled(isCreating || downloaded.count != LegacyInstallerAssembler.componentNames.count)
                if isCreating {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 16)
        .appAlert(item: $activeAlert) { alert in
            if case .replaceFile = alert, let replacement {
                startDownload(replacement, replacing: true)
            }
        }
        .onAppear(perform: refreshDownloads)
        .onChange(of: manager.activeDownloadCount) { refreshDownloads() }
        .onChange(of: manager.completedDownloads) { refreshDownloads() }
        .onReceive(NotificationCenter.default.publisher(for: .downloadPathChanged)) { _ in refreshDownloads() }
    }

    private func refreshDownloads() {
        let root = Prefs.downloadURL
        let access = Prefs.startAccessingDownloadURL()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        downloaded = Set(product.installerComponents.compactMap { package in
            let path = filename(for: package)
            let values = try? root.appendingPathComponent(path).resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            return values?.isRegularFile == true && values?.fileSize == package.size
                && !manager.isDownloading(filename: path) ? path : nil
        })
    }

    private func download(_ package: Package) {
        guard manager.canStartNewDownload else {
            activeAlert = .maxDownloads
            return
        }
        let root = Prefs.downloadURL
        let access = Prefs.startAccessingDownloadURL()
        defer { if access { root.stopAccessingSecurityScopedResource() } }
        if FileManager.default.fileExists(atPath: root.appendingPathComponent(filename(for: package)).path) {
            replacement = package
            activeAlert = .replaceFile(filename: filename(for: package))
        } else {
            startDownload(package, replacing: false)
        }
    }

    private func startDownload(_ package: Package, replacing: Bool) {
        do {
            _ = try manager.startDownload(url: URL(string: package.url), filename: filename(for: package), replacing: replacing)
            refreshDownloads()
        } catch {
            activeAlert = .downloadError(message: error.localizedDescription)
        }
    }

    private func openBaseSystem() {
        let root = Prefs.downloadURL
        let access = Prefs.startAccessingDownloadURL()
        let image = root.appendingPathComponent(product.componentFolder).appendingPathComponent("BaseSystem.dmg")
        NSWorkspace.shared.open(image, configuration: NSWorkspace.OpenConfiguration()) { _, error in
            if access { root.stopAccessingSecurityScopedResource() }
            Task { @MainActor in
                if let error { showCreationError(error) }
            }
        }
    }

    private func createInstaller() {
        let root = Prefs.downloadURL
        let folder = root.appendingPathComponent(product.componentFolder)
        let componentSizes = sizes
        let access = Prefs.startAccessingDownloadURL()
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = false
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        panel.message = NSLocalizedString("Select the Install macOS app on the BaseSystem image you opened for this download. Do not select an installer from Applications or another release.", comment: "Choose legacy installer source")
        assemblyState.activeFolders.insert(folder.path)

        panel.begin { response in
            guard response == .OK, let source = panel.url else {
                if access { root.stopAccessingSecurityScopedResource() }
                assemblyState.activeFolders.remove(folder.path)
                return
            }
            let sourceAccess = source.startAccessingSecurityScopedResource()
            Task { @MainActor in
                defer {
                    if sourceAccess { source.stopAccessingSecurityScopedResource() }
                    if access { root.stopAccessingSecurityScopedResource() }
                    assemblyState.activeFolders.remove(folder.path)
                    refreshDownloads()
                }

                do {
                    let output = try await Task.detached(priority: .userInitiated) {
                        try LegacyInstallerAssembler.assemble(sourceApp: source, folder: folder, sizes: componentSizes)
                    }.value
                    NSWorkspace.shared.activateFileViewerSelecting([output])
                } catch {
                    showCreationError(error)
                }
            }
        }
    }

    private func showCreationError(_ error: Error) {
        print("Legacy installer assembly: \(error.localizedDescription)")
        activeAlert = .installerCreation(
            title: NSLocalizedString("Error Creating Installer", comment: ""),
            message: error.localizedDescription
        )
    }
}

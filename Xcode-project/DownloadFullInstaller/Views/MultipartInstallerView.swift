import SwiftUI

struct MultipartInstallerView: View {
    @ObservedObject var product: Product
    @ObservedObject private var manager = MultiDownloadManager.shared
    @State private var activeAlert: AppAlertType?
    @State private var replacement: Package?
    @State private var downloaded = Set<String>()

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
            Text(NSLocalizedString("Download all six components below into the same folder. These Intel installers cannot install macOS on Apple Silicon.", comment: "Multipart installer instructions"))
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
                    .disabled(manager.isDownloading(filename: filename(for: package)))
                }
                .contextMenu {
                    Button(NSLocalizedString("Copy Download URL", comment: "")) {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(package.url, forType: .string)
                    }
                }
            }

            if product.installerComponents.count != LegacyInstallerComponents.names.count {
                Text(NSLocalizedString("This catalog does not provide all six required installer components. Try the Regular catalog.", comment: "Incomplete multipart catalog entry"))
                    .foregroundStyle(.secondary)
            }
            Text(NSLocalizedString("Do not open InstallESDDmg.pkg; it is not a standalone installer. After all six downloads finish, run gibMacOS's BuildmacOSInstallApp.command on macOS and select this folder to assemble the installer app. Download Full Installer does not assemble it automatically.", comment: "Multipart installer external assembly instructions"))
                .font(.callout.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            Link(destination: URL(string: "https://github.com/corpnewt/gibMacOS")!) {
                Text(NSLocalizedString("Get gibMacOS (external assembly tool)", comment: "Link to the external legacy installer builder"))
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
}

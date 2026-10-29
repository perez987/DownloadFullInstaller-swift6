import AppKit
import Combine

@MainActor
final class LegacyInstallerBuildManager: ObservableObject {
    static let shared = LegacyInstallerBuildManager()

    @Published private(set) var componentFolder: URL?
    @Published private(set) var status = ""
    @Published var activeAlert: AppAlertType?

    var isBuilding: Bool { componentFolder != nil }

    func isUsing(_ file: URL) -> Bool {
        file.deletingLastPathComponent().standardizedFileURL.path
            == componentFolder?.standardizedFileURL.path
    }

    func createInstaller(for product: Product) async {
        guard !isBuilding else { return }
        let downloads = Prefs.downloadURL
        let access =
            Prefs.downloadURLRequiresSecurityScope
            && downloads.startAccessingSecurityScopedResource()
        defer { if access { downloads.stopAccessingSecurityScopedResource() } }
        let folder = downloads.appendingPathComponent(
            product.componentFolder,
            isDirectory: true
        )
        let sizes = Dictionary(
            uniqueKeysWithValues: product.installerComponents.compactMap {
                package in
                URL(string: package.url).map {
                    ($0.lastPathComponent, package.size)
                }
            }
        )
        componentFolder = folder
        defer {
            componentFolder = nil
            status = ""
        }

        var volumeToEject: URL?
        var volumeAccess: URL?
        defer { volumeAccess?.stopAccessingSecurityScopedResource() }
        var result: URL?
        var failure: String?
        var canceled = false
        var imageOpened = false
        do {
            guard
                !product.installerComponents.contains(where: {
                    MultiDownloadManager.shared.isDownloading(
                        filename:
                            "\(product.componentFolder)/\(URL(string: $0.url)?.lastPathComponent ?? "")"
                    )
                })
            else {
                throw LegacyInstallerBuilder.BuildError.incompleteComponents
            }
            try LegacyInstallerBuilder.validateComponents(
                in: folder,
                expectedSizes: sizes
            )
            guard
                let mountedVolumes = FileManager.default.mountedVolumeURLs(
                    includingResourceValuesForKeys: nil
                )
            else {
                throw CocoaError(.fileReadUnknown)
            }
            let existingVolumes = Set(
                mountedVolumes.map { $0.standardizedFileURL.path }
            )
            status = NSLocalizedString(
                "Opening BaseSystem.dmg...",
                comment: "Installer assembly status"
            )
            try await openBaseSystem(
                folder.appendingPathComponent("BaseSystem.dmg")
            )
            imageOpened = true

            status = NSLocalizedString(
                "Select the mounted Base System volume...",
                comment: "Installer assembly status"
            )
            if let volume = await selectBaseSystemVolume() {
                if volume.startAccessingSecurityScopedResource() {
                    volumeAccess = volume
                }
                let values = try volume.resourceValues(forKeys: [
                    .volumeURLKey, .volumeIsReadOnlyKey,
                ])
                guard
                    values.volume?.standardizedFileURL.path
                        == volume.standardizedFileURL.path,
                    values.volumeIsReadOnly == true,
                    volume.deletingLastPathComponent().standardizedFileURL.path
                        == "/Volumes"
                else {
                    throw LegacyInstallerBuilder.BuildError.invalidInstaller
                }
                let sourceApp = try LegacyInstallerBuilder.installerApp(
                    in: volume
                )
                if let release = product.osName,
                    sourceApp.lastPathComponent
                        != "Install macOS \(release).app"
                {
                    throw LegacyInstallerBuilder.BuildError.invalidInstaller
                }
                // Never eject an image that was already mounted before this operation.
                if !existingVolumes.contains(volume.standardizedFileURL.path) {
                    volumeToEject = volume
                }
                status = NSLocalizedString(
                    "Assembling installer app. Copying large files may take several minutes...",
                    comment: "Installer assembly status"
                )
                result = try await Task.detached(priority: .userInitiated) {
                    try LegacyInstallerBuilder.build(
                        from: sourceApp,
                        components: folder,
                        expectedSizes: sizes
                    )
                }.value
            } else {
                canceled = true
            }
        } catch {
            failure = error.localizedDescription
            print("Legacy installer creation: \(error)")
        }

        var ejectWarning: String?
        if let volumeToEject {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: volumeToEject)
            } catch {
                ejectWarning = String(
                    format: NSLocalizedString(
                        "The installer image could not be ejected. Eject it in Finder. Error: %@",
                        comment: "Disk image cleanup failed"
                    ),
                    error.localizedDescription
                )
                print("Legacy installer image eject: \(error)")
            }
        } else if imageOpened {
            ejectWarning = NSLocalizedString(
                "BaseSystem.dmg may still be mounted. Eject the Base System image in Finder when finished.",
                comment: "Image remains mounted after selection or cancellation"
            )
        }
        if let result {
            NSWorkspace.shared.activateFileViewerSelecting([result])
            let appName = result.lastPathComponent
            let osName = result.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "Install ", with: "")
            var message = String(
                format: NSLocalizedString(
                    "The installer app has been created alongside the downloaded %@ components, under the name \"%@\".",
                    comment: "Installer output location: OS name, app file name"
                ),
                osName,
                appName
            )
            message +=
                "\n\n"
                + NSLocalizedString(
                    "This is an Intel installer. Creating the app does not make it compatible with Apple Silicon or unsupported Macs.",
                    comment: "Installer compatibility warning"
                )
            if let ejectWarning { message += "\n\n" + ejectWarning }
            activeAlert = .installerCreation(
                title: NSLocalizedString("Success", comment: ""),
                message: message
            )
        } else if let failure {
            var message = failure
            if let ejectWarning { message += "\n\n" + ejectWarning }
            activeAlert = .installerCreation(
                title: NSLocalizedString(
                    "Error Creating Installer",
                    comment: ""
                ),
                message: message
            )
        } else if canceled {
            activeAlert = .installerCreation(
                title: NSLocalizedString(
                    "Installer creation canceled",
                    comment: "Installer canceled"
                ),
                message: ejectWarning ?? ""
            )
        }
    }

    // Mounts with -nobrowse so Finder does not open a window for the volume.
    private func openBaseSystem(_ image: URL) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
            process.arguments = [
                "attach", "-nobrowse", "-readonly", "-noautoopen", image.path,
            ]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CocoaError(.fileReadUnknown)
            }
        }.value
    }

    private func selectBaseSystemVolume() async -> URL? {
        let panel = NSOpenPanel()
        panel.title = NSLocalizedString(
            "Select Base System Volume",
            comment: "Installer image authorization"
        )
        panel.message = NSLocalizedString(
            "Wait for BaseSystem.dmg to mount, then select its Base System volume in the /Volumes folder. Select the volume itself, not the installer app inside it. This grants Download Full Installer access to copy the app. Cancel if the image did not mount.",
            comment: "Sandbox source authorization"
        )
        panel.prompt = NSLocalizedString(
            "Select",
            comment: "Authorize installer volume"
        )
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                Task { @MainActor in
                    continuation.resume(
                        returning: response == .OK ? panel.url : nil
                    )
                }
            }
        }
    }
}

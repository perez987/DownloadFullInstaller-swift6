import Foundation

enum LegacyInstallerAssembler {
    static let componentNames = [
        "BaseSystem.dmg", "BaseSystem.chunklist", "InstallESDDmg.pkg",
        "InstallInfo.plist", "AppleDiagnostics.dmg", "AppleDiagnostics.chunklist",
    ]

    static func validateComponents(in folder: URL, sizes: [String: Int]) throws {
        for name in componentNames {
            let file = folder.appendingPathComponent(name)
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true, let size = sizes[name], size > 0,
                  values.fileSize == size else {
                throw NSError(
                    domain: "LegacyInstallerAssembler", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: String(
                        format: NSLocalizedString("Installer component %@ is missing or incomplete. Download it again.", comment: "Invalid legacy installer component"),
                        name
                    )]
                )
            }
        }
    }

    // Build in a staging directory so failure never leaves a success-shaped .app.
    static func assemble(sourceApp: URL, folder: URL, sizes: [String: Int]) throws -> URL {
        let files = FileManager.default
        try validateComponents(in: folder, sizes: sizes)
        let sourceInfo = sourceApp.appendingPathComponent("Contents/Info.plist")
        let infoData = try Data(contentsOf: sourceInfo)
        guard sourceApp.pathExtension == "app",
              let info = try PropertyListSerialization.propertyList(from: infoData, format: nil) as? [String: Any],
              let identifier = info["CFBundleIdentifier"] as? String,
              (identifier == "com.apple.InstallAssistant" || identifier.hasPrefix("com.apple.InstallAssistant."))
        else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("The selected app is not a macOS installer. Select the installer app on the mounted BaseSystem image.", comment: "Invalid legacy installer bundle"),
            ])
        }

        let mediaTool = sourceApp.appendingPathComponent("Contents/Resources/createinstallmedia")
        let attributes = try files.attributesOfItem(atPath: mediaTool.path)
        // The file chooser grants read access, not execution. Inspect the stored
        // mode instead of isExecutableFile, which tests execution permission.
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.int64Value > 0,
              let permissions = attributes[.posixPermissions] as? NSNumber,
              permissions.intValue & 0o111 != 0 else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("The selected installer has an invalid createinstallmedia tool. Select the installer app on the mounted BaseSystem image.", comment: "Invalid legacy installer media tool"),
            ])
        }

        let installInfoData = try Data(contentsOf: folder.appendingPathComponent("InstallInfo.plist"))
        guard var installInfo = try PropertyListSerialization.propertyList(from: installInfoData, format: nil) as? [String: Any],
              var payload = installInfo["Payload Image Info"] as? [String: Any],
              let payloadURL = payload["URL"] as? String,
              payloadURL.hasSuffix("InstallESDDmg.pkg"),
              let payloadID = payload["id"] as? String,
              payloadID == "com.apple.pkg.InstallESDDmg"
        else {
            throw CocoaError(.fileReadCorruptFile, userInfo: [
                NSLocalizedDescriptionKey: NSLocalizedString("InstallInfo.plist does not contain the expected installer payload metadata. Download this component again.", comment: "Invalid legacy installer payload"),
            ])
        }
        payload["URL"] = "InstallESD.dmg"
        payload["id"] = "com.apple.dmg.InstallESD"
        payload.removeValue(forKey: "chunklistURL")
        payload.removeValue(forKey: "chunklistid")
        installInfo["Payload Image Info"] = payload
        let patchedInfo = try PropertyListSerialization.data(fromPropertyList: installInfo, format: .xml, options: 0)

        let output = folder.appendingPathComponent(sourceApp.lastPathComponent)
        guard !files.fileExists(atPath: output.path) else {
            throw CocoaError(.fileWriteFileExists)
        }
        let staging = folder.appendingPathComponent(".assembling-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            let stagedApp = staging.appendingPathComponent(sourceApp.lastPathComponent)
            try files.copyItem(at: sourceApp, to: stagedApp)
            let support = stagedApp.appendingPathComponent("Contents/SharedSupport", isDirectory: true)
            try files.createDirectory(at: support, withIntermediateDirectories: true)
            for name in componentNames where name != "InstallInfo.plist" {
                let targetName = name == "InstallESDDmg.pkg" ? "InstallESD.dmg" : name
                try files.copyItem(at: folder.appendingPathComponent(name), to: support.appendingPathComponent(targetName))
            }
            try patchedInfo.write(to: support.appendingPathComponent("InstallInfo.plist"), options: .atomic)
            try files.moveItem(at: stagedApp, to: output)
        } catch {
            do {
                try files.removeItem(at: staging)
            } catch let cleanupError {
                print("Legacy installer staging cleanup: \(cleanupError.localizedDescription)")
            }
            throw error
        }
        do {
            try files.removeItem(at: staging)
        } catch {
            print("Legacy installer staging cleanup: \(error.localizedDescription)")
        }
        return output
    }
}

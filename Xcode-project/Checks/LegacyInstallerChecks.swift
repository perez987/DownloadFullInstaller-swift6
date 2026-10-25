import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

@main
struct LegacyInstallerChecks {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func expectFailure(_ operation: () throws -> Void) {
        do {
            try operation()
            preconditionFailure("Expected an error")
        } catch {}
    }

    static func writePlist(_ value: [String: Any], to url: URL) throws {
        try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0).write(to: url)
    }

    static func main() throws {
        require(MetaInfo(installAssistantPackageIdentifiers: ["OSInstall": "com.apple.mpkg.OSInstall"]).isInstaller,
                "Legacy installer marker rejected")
        require(MetaInfo(installAssistantPackageIdentifiers: ["SharedSupport": "com.apple.pkg.InstallAssistant.macOSBigSur"]).isInstaller,
                "Modern installer marker rejected")
        require(!MetaInfo(installAssistantPackageIdentifiers: ["OSInstall": "unrelated.update"]).isInstaller,
                "Unrelated update accepted")
        require(!MetaInfo(installAssistantPackageIdentifiers: ["SharedSupport": "unrelated.package"]).isInstaller,
                "Unrelated shared support accepted")
        require(!MetaInfo(installAssistantPackageIdentifiers: nil).isInstaller, "Missing metadata accepted")

        let files = FileManager.default
        let root = files.temporaryDirectory.appendingPathComponent("LegacyInstallerChecks-\(UUID().uuidString)")
        try files.createDirectory(at: root, withIntermediateDirectories: false)
        defer {
            do { try files.removeItem(at: root) }
            catch { print("Fixture cleanup failed: \(error)") }
        }

        let source = root.appendingPathComponent("Install macOS High Sierra.app")
        let resources = source.appendingPathComponent("Contents/Resources")
        try files.createDirectory(at: resources, withIntermediateDirectories: true)
        try writePlist(["CFBundleIdentifier": "com.apple.InstallAssistant.HighSierra"],
                       to: source.appendingPathComponent("Contents/Info.plist"))
        let executable = resources.appendingPathComponent("createinstallmedia")
        try Data("fixture only".utf8).write(to: executable)
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

        let components = root.appendingPathComponent("macOS-001-TEST")
        try files.createDirectory(at: components, withIntermediateDirectories: false)
        for name in LegacyInstallerAssembler.componentNames {
            try Data("Fixture: \(name)".utf8).write(to: components.appendingPathComponent(name))
        }
        let payload: [String: Any] = [
            "URL": "https://example.invalid/InstallESDDmg.pkg",
            "id": "com.apple.pkg.InstallESDDmg",
            "chunklistURL": "obsolete.chunklist",
            "chunklistid": "obsolete",
            "unchanged": "preserve this",
        ]
        let plist = components.appendingPathComponent("InstallInfo.plist")
        try writePlist(["Payload Image Info": payload, "Other": "preserved"], to: plist)
        let originalInfo = try Data(contentsOf: plist)
        let sizes = try Dictionary(uniqueKeysWithValues: LegacyInstallerAssembler.componentNames.map { name in
            (name, try Data(contentsOf: components.appendingPathComponent(name)).count)
        })

        try LegacyInstallerAssembler.validateComponents(in: components, sizes: sizes)
        let output = try LegacyInstallerAssembler.assemble(sourceApp: source, folder: components, sizes: sizes)
        let support = output.appendingPathComponent("Contents/SharedSupport")
        for name in LegacyInstallerAssembler.componentNames where name != "InstallInfo.plist" {
            let target = name == "InstallESDDmg.pkg" ? "InstallESD.dmg" : name
            let actual = try Data(contentsOf: support.appendingPathComponent(target))
            let original = try Data(contentsOf: components.appendingPathComponent(name))
            require(actual == original, "Component data changed: \(name)")
        }
        require(!files.fileExists(atPath: support.appendingPathComponent("InstallESDDmg.pkg").path), "ESD was not renamed")
        let patched = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: support.appendingPathComponent("InstallInfo.plist")), format: nil
        ) as! [String: Any]
        let patchedPayload = patched["Payload Image Info"] as! [String: Any]
        require(patchedPayload["URL"] as? String == "InstallESD.dmg", "Wrong ESD URL")
        require(patchedPayload["id"] as? String == "com.apple.dmg.InstallESD", "Wrong ESD ID")
        require(patchedPayload["chunklistURL"] == nil && patchedPayload["chunklistid"] == nil, "Stale chunklist references")
        require(patchedPayload["unchanged"] as? String == "preserve this", "Unrelated payload metadata lost")
        require(patched["Other"] as? String == "preserved", "Unrelated plist metadata lost")
        let unchangedInfo = try Data(contentsOf: plist)
        require(unchangedInfo == originalInfo, "Source plist was modified")
        require(files.isExecutableFile(atPath: output.appendingPathComponent("Contents/Resources/createinstallmedia").path),
                "Installer executable permissions lost")

        expectFailure {
            _ = try LegacyInstallerAssembler.assemble(sourceApp: source, folder: components, sizes: sizes)
        }
        require(files.fileExists(atPath: output.path), "Existing output was overwritten")
        try files.removeItem(at: output)

        let esd = components.appendingPathComponent("InstallESDDmg.pkg")
        let originalESD = try Data(contentsOf: esd)
        try Data().write(to: esd)
        expectFailure { try LegacyInstallerAssembler.validateComponents(in: components, sizes: sizes) }
        expectFailure { _ = try LegacyInstallerAssembler.assemble(sourceApp: source, folder: components, sizes: sizes) }
        try files.removeItem(at: esd)
        expectFailure { try LegacyInstallerAssembler.validateComponents(in: components, sizes: sizes) }
        try originalESD.write(to: esd)

        try files.setAttributes([.posixPermissions: 0o644], ofItemAtPath: executable.path)
        expectFailure { _ = try LegacyInstallerAssembler.assemble(sourceApp: source, folder: components, sizes: sizes) }
        try files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try writePlist(["CFBundleIdentifier": "com.example.NotAnInstaller"],
                       to: source.appendingPathComponent("Contents/Info.plist"))
        expectFailure { _ = try LegacyInstallerAssembler.assemble(sourceApp: source, folder: components, sizes: sizes) }
        try writePlist(["CFBundleIdentifier": "com.apple.InstallAssistant.HighSierra"],
                       to: source.appendingPathComponent("Contents/Info.plist"))

        try writePlist(["Payload Image Info": ["URL": "Unexpected.dmg"]], to: plist)
        var invalidSizes = sizes
        invalidSizes["InstallInfo.plist"] = try Data(contentsOf: plist).count
        expectFailure { _ = try LegacyInstallerAssembler.assemble(sourceApp: source, folder: components, sizes: invalidSizes) }
        try originalInfo.write(to: plist)
        // Force a copy failure after staging has started.
        let conflictingSupport = source.appendingPathComponent("Contents/SharedSupport")
        try files.createDirectory(at: conflictingSupport, withIntermediateDirectories: false)
        try Data().write(to: conflictingSupport.appendingPathComponent("BaseSystem.dmg"))
        expectFailure { _ = try LegacyInstallerAssembler.assemble(sourceApp: source, folder: components, sizes: sizes) }
        require(!files.fileExists(atPath: output.path), "Failed assembly published an output app")
        let remaining = try files.contentsOfDirectory(atPath: components.path)
        require(!remaining.contains { $0.hasPrefix(".assembling-") }, "Failed assembly left staging data")

        for (buildKey, versionKey, build, version) in [
            ("BUILD", "VERSION", "17G66", "10.13.6"),
            ("macOSProductBuildVersion", "macOSProductVersion", "18G103", "10.14.6"),
            ("BUILD", "VERSION", "24G90", "15.6"),
        ] {
            let xml = """
            <?xml version="1.0"?>
            <installer-gui-script><title>Install macOS</title>
            <auxinfo><dict><key>\(buildKey)</key><string>\(build)</string>
            <key>\(versionKey)</key><string>\(version)</string></dict></auxinfo>
            </installer-gui-script>
            """
            let parser = XMLParser(data: Data(xml.utf8))
            let delegate = DistParserDelegate()
            parser.delegate = delegate
            require(parser.parse(), "Distribution XML did not parse")
            require(delegate.buildVersion == build && delegate.productVersion == version, "Distribution metadata mismatch")
        }
        require(nameOS["17"] == "High Sierra" && nameOS["18"] == "Mojave", "Legacy release mapping missing")
        print("Legacy installer fixture checks passed")
    }
}

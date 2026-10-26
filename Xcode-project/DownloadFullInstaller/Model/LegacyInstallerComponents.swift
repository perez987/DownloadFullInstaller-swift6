import Foundation

enum LegacyInstallerComponents {
    // Inputs to gibMacOS's BuildmacOSInstallApp, not standalone installable packages.
    static let names = [
        "BaseSystem.dmg", "BaseSystem.chunklist", "InstallESDDmg.pkg",
        "InstallInfo.plist", "AppleDiagnostics.dmg", "AppleDiagnostics.chunklist",
    ]
}

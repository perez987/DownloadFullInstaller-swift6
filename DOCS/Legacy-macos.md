# Download legacy macOS

### Preface

There may be users interested in obtaining legacy versions of macOS, prior to Big Sur.  [5T33Z0](https://github.com/5T33Z0) has proposed adding this to Download Full Installer as a way to complement the app or add an extra feature. The most significant challenge is finding direct links to legacy versions of macOS that can be integrated into Download Full Installer without requiring extensive code modifications.

There is a support article by Apple on "[How to download and install macOS](https://support.apple.com/en-us/102662)” with a section called "Use a web browser for older versions" that contains direct download links for macOS Lion to Sierra:

- [macOS Sierra 10.12](http://updates-http.cdn-apple.com/2019/cert/061-39476-20191023-48f365f4-0015-4c41-9f44-39d3d2aca067/InstallOS.dmg) 
- [OS X El Capitan 10.11](http://updates-http.cdn-apple.com/2019/cert/061-41424-20191024-218af9ec-cf50-4516-9011-228c78eda3d2/InstallMacOSX.dmg) 
- [OS X Yosemite 10.10](http://updates-http.cdn-apple.com/2019/cert/061-41343-20191023-02465f92-3ab5-4c92-bfe2-b725447a070d/InstallMacOSX.dmg) 
- [Mac OS X Mountain Lion 10.8](https://updates.cdn-apple.com/2021/macos/031-0627-20210614-90D11F33-1A65-42DD-BBEA-E1D9F43A6B3F/InstallMacOSX.dmg) 
- [Mac OS X Lion 10.7](https://updates.cdn-apple.com/2021/macos/041-7683-20210614-E610947E-C7CE-46EB-8860-D26D71F0D3EA/InstallMacOSX.dmg)

These legacy systems use a different method than Big Sur and later systems. While the latter download a PKG installer, differentiate between versions, that can easily be converted into the Install macOS app, the legacy systems have a single link to the latest available version of each system and download a DMG disk image containing the PKG installer.

The disk images can use the same download queue as modern installers, but creating an installer app requires opening the downloaded image in Finder and running the package inside it.

### Implementation

Starting with version 6.0.0, the five legacy macOS versions appear at the end of the main window's left-hand installer list. Select a release to display its download card and disk-image instructions in the right-hand pane. A separate legacy window is no longer needed.

Legacy downloads are managed similarly to modern downloads:

- They can be canceled before completion
- They share the same queue and three-download limit as installers and firmware
- Progress remains visible when switching releases or content types
- Completed images can be revealed in Finder
- The download destination folder is the one configured in the app settings
- The selected software update catalog does not affect these fixed Apple download links.

### Catalog-based installers: High Sierra and Mojave

The five fixed disk-image links above remain independent of the catalog. Additional pre-Big Sur installers are discovered dynamically in Apple's software update catalogs, using the `OSInstall = com.apple.mpkg.OSInstall` metadata marker also recognized by [gibMacOS](https://github.com/corpnewt/gibMacOS). The previous catalog filter only recognized the newer `SharedSupport` marker.

High Sierra and Mojave can therefore appear under **Available Releases** rather than the fixed-link legacy section. Catalina can also be discovered if Apple publishes a matching entry; no particular release or build is guaranteed. Try the **Regular** catalog if a seed catalog does not contain older installers. No App Store links or third-party installer mirrors are used.

Unlike a modern `InstallAssistant.pkg`, `InstallESDDmg.pkg` needs the other five components in the same folder. A multipart card offers the six files:

| File | Purpose |
| --- | --- |
| `BaseSystem.dmg` | Base system image containing the installer application |
| `BaseSystem.chunklist` | Base system chunk metadata |
| `InstallESDDmg.pkg` | Main installation image; open it to create the installer app |
| `InstallInfo.plist` | Image references used by the installer |
| `AppleDiagnostics.dmg` | Diagnostics image |
| `AppleDiagnostics.chunklist` | Diagnostics chunk metadata |

#### Download and create the app

1. Select a catalog-based legacy release, then download **all six components** using their individual buttons. They share the existing three-transfer limit, cancellation, retry, replacement confirmation, and Finder actions. Start the remaining files as slots become available.
2. Wait for all six green checkmarks. Files retain their original names under `macOS-<catalog-product-ID>` inside the configured download folder, preventing collisions between releases/builds.
3. Open `InstallESDDmg.pkg` from that folder and follow the instructions to create the installer app.

These are **Intel** installers. Downloading them on macOS 15+ does not make them compatible with Apple Silicon or permit installation on unsupported hardware. No Mavericks download has been added.

#### Validation on macOS

Build the application with Xcode 26, then check High Sierra and Mojave in the Regular catalog if available. Exercise all six downloads, the three-download limit, cancel/retry, replacement, switching releases, and a custom download folder. Open `InstallESDDmg.pkg` from the product folder and confirm it creates the installer app. Also check a modern Big Sur-or-newer PKG and the five fixed legacy DMGs.

The standalone fixture checks in `Xcode-project/Checks/LegacyInstallerChecks.swift` exercise the catalog metadata and distribution parsing logic without downloading multi-gigabyte installers:

```sh
swiftc -swift-version 6 \
  Xcode-project/DownloadFullInstaller/Model/LegacyInstallerComponents.swift \
  Xcode-project/DownloadFullInstaller/Model/DistParserDelegate.swift \
  Xcode-project/DownloadFullInstaller/Model/MetaInfo.swift \
  Xcode-project/DownloadFullInstaller/Model/OSNames.swift \
  Xcode-project/Checks/LegacyInstallerChecks.swift \
  -o /tmp/LegacyInstallerChecks && /tmp/LegacyInstallerChecks
```

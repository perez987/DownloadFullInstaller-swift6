# Release notes

## Unreleased

- Discover multipart pre-Big Sur installers (including High Sierra and Mojave when available) through Apple's `OSInstall` catalog metadata.
- Download the six required components into separate product folders using the shared download queue. Do not treat an ESD component as a standalone InstallAssistant package.
- After downloading the six components, the user opens `InstallESDDmg.pkg` and follows its instructions to create the installer app. The in-app BaseSystem/assembly buttons were removed.
- Parse both legacy and modern distribution version/build keys and identify releases from their build numbers.
- Show the release name instead of the unresolved `SU_TITLE` key on Catalina, Mojave, and High Sierra installer cards.
- Make the copy-download-URL context menu available across the entire modern installer and firmware card, including empty space.
- Show only the newest available multipart installer for each of High Sierra, Mojave, and Catalina in the detail panel, without changing the catalog or download behavior.

Availability depends on Apple's catalogs. This change requires macOS/Xcode and real-installer verification before release.

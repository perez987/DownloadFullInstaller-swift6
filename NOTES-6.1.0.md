# Release notes

## Unreleased

- Keep the Legacy macOS Installers section collapsed on launch. Use the chevron beside its header to show or hide the five disk-image installers while modern and multipart releases load normally.
- Discover multipart pre-Big Sur installers (including High Sierra and Mojave when available) through Apple's `OSInstall` catalog metadata.
- Download the six required components into separate product folders using the shared download queue. Do not treat an ESD component as a standalone InstallAssistant package.
- After downloading the six components, the user opens `InstallESDDmg.pkg` and follows its instructions to create the installer app
- Parse both legacy and modern distribution version/build keys and identify releases from their build numbers
- Show only the newest available multipart installer for each of High Sierra, Mojave, and Catalina in the detail panel, without changing the catalog or download behavior.

Availability depends on Apple's catalogs.
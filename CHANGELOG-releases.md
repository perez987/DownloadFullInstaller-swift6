# Release notes

## Unreleased

- Discover multipart pre-Big Sur installers (including High Sierra and Mojave when available) through Apple's `OSInstall` catalog metadata.
- Download the six required components into separate product folders using the shared download queue. Do not treat an ESD component as a standalone InstallAssistant package.
- Assemble legacy installer apps natively after the user mounts BaseSystem and selects its installer app, preserving the sandbox and original downloads.
- Parse both legacy and modern distribution version/build keys and identify releases from their build numbers.

Availability depends on Apple's catalogs. This change requires macOS/Xcode and real-installer verification before release; Linux cannot validate the sandboxed assembly flow.

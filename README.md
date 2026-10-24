# Mac VM

A small macOS virtual machine launcher built with Swift, AppKit, and Apple's Virtualization framework. It installs macOS from a local IPSW restore image and boots the same VM on subsequent launches. No Homebrew or third-party virtualization app is required.

The launcher never downloads an installer. You supply `Data/Restore.ipsw`.

## Requirements

- A Mac with Apple silicon.
- macOS compatible with the chosen restore image.
- Apple's Command Line Tools or Xcode, including `swiftc` and `codesign`. To install the Command Line Tools, run `xcode-select --install`.
- Enough memory for the guest's default 8 GiB allocation plus the host, and disk space for the restore image and guest data. The virtual disk has a 64 GiB capacity and grows as data is written.

## Quick start

Run these commands from the repository directory.

1. Create the local data directory:

   ```sh
   mkdir -p Data
   ```

2. Download a compatible macOS `.ipsw` restore image using the sources below. Rename it to `Restore.ipsw` and place it in `Data/`.

3. Build and launch:

   ```sh
   ./build.sh
   open 'Mac VM.app'
   ```

On first launch, the app creates the virtual disk and hardware files, installs macOS, and boots into Setup Assistant. Keep the app open during installation, then complete setup inside the VM. Later launches boot the existing disk without requiring the installer.

Shut down using the guest's Apple menu before closing the app. Run only one instance at a time.

## Restore images

Browse the [Apple Virtual Machine IPSW catalog](https://ipsw.me/VirtualMac2,1/) for available versions. This is a third-party index whose software download links point to Apple's servers. Select a macOS restore image for the virtual Mac and save it as `Data/Restore.ipsw`.

For example, the image used during initial development was **macOS 27.0.1, build 26A434**, downloaded from Apple's CDN as `UniversalMac_27.0.1_26A434_Restore.ipsw`:

[Download that restore image from Apple](https://updates.cdn-apple.com/2026FallFCS/59241290-5d51-4ca8-9df4-31624b9a4eac/UniversalMac_27.0.1_26A434_Restore.ipsw)

Apple's official programmatic discovery API is [`VZMacOSRestoreImage.latestSupported`](https://developer.apple.com/documentation/virtualization/vzmacosrestoreimage/latestsupported). It returns metadata and a download URL for the latest image supported by the host. The launcher uses only the local image and checks compatibility before installation.

Replacing `Restore.ipsw` changes the installer used for a fresh VM. To upgrade an existing guest, use Software Update inside the VM.

## Configuration

Defaults:

| Resource | Value |
| --- | --- |
| CPU | 4 virtual cores |
| Memory | 8 GiB |
| Disk | 64 GiB capacity |
| Display | 1920 × 1200 |
| Network | NAT through the host |
| Input and audio | Keyboard, pointer, audio output |

Edit `VM.swift` to change these values:

- **CPU and RAM:** change the defaults in `makeVM(cpuCount:memorySize:)` and the corresponding `max(...)` values in the installation call. Installation respects the restore image's minimum requirements.
- **Disk capacity:** change the size passed to `disk.truncate(atOffset:)`. This applies to newly created disks only.
- **Display:** edit `VZMacGraphicsDisplayConfiguration`.

Close the app and run `./build.sh` after changing the source. The build uses local ad hoc signing with the virtualization entitlement. Host folder sharing is not configured.

## Files and storage

| Path | Purpose |
| --- | --- |
| `VM.swift` | Launcher source |
| `Info.plist` | App metadata |
| `AppIcon.icns` | Apple logo app icon |
| `entitlements.plist` | Virtualization entitlement used when signing |
| `build.sh` | Creates, compiles, signs, and verifies the app bundle |
| `Mac VM.app/` | Generated app; can be deleted and rebuilt |
| `Data/Restore.ipsw` | Local installer for new or incomplete installations |
| `Data/Disk.img` | Guest OS, applications, accounts, and personal files |
| `Data/HardwareModel` | Saved virtual hardware model |
| `Data/MachineIdentifier` | Persistent VM identity |
| `Data/AuxiliaryStorage` | Guest boot and firmware storage |
| `Data/Installing` | Marker that lets the next launch retry an interrupted installation |

Keep `Data/` beside `Mac VM.app` when moving the app. Keep generated app and data files out of version control. The build script recreates the app bundle and does not modify `Data/`.

To back up the VM, shut it down, close the app, and copy the entire `Data/` folder. Preserve the disk, hardware model, machine identifier, and auxiliary storage together.

To start fresh, shut down the VM, close the app, and delete `Data/Disk.img`. This removes all guest data. Keep `Data/Restore.ipsw`, then reopen the app to create and install a new VM. Its hardware identity and auxiliary storage are recreated automatically.

## Troubleshooting

- **Missing installer:** place a compatible image at `Data/Restore.ipsw`. There is no automatic download.
- **Incompatible installer:** choose a restore image supported by the host Mac and macOS version.
- **Interrupted installation:** reopen the app with the local installer still present. The `Installing` marker triggers another installation attempt.
- **Missing build output directory:** use `./build.sh` rather than running `swiftc` alone. The script creates the bundle directories and copies the required metadata before compiling.

See [Apple's installation guide](https://developer.apple.com/documentation/virtualization/installing-macos-on-a-virtual-machine) for details about macOS virtualization and restore images.

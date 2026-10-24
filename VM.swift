import AppKit
import Virtualization

let data = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Data")
let manager = FileManager.default
func file(_ name: String) -> URL { data.appendingPathComponent(name) }
func exists(_ name: String) -> Bool { manager.fileExists(atPath: file(name).path) }
struct VMError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

@MainActor
final class Controller: NSObject, NSApplicationDelegate, NSWindowDelegate, @preconcurrency VZVirtualMachineDelegate {
    var window: NSWindow!
    var vm: VZVirtualMachine?
    var installing = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Mac VM"
        window.delegate = self
        window.center(); window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        Task {
            do { try await start() }
            catch { showError(error); NSApp.terminate(nil) }
        }
    }
    func start() async throws {
        try manager.createDirectory(at: data, withIntermediateDirectories: true)
        let needsDisk = !exists("Disk.img")
        if needsDisk || exists("Installing") {
            guard exists("Restore.ipsw") else {
                throw VMError("Place a compatible macOS installer at \(file("Restore.ipsw").path). Nothing will be downloaded.")
            }
            let restore = try await VZMacOSRestoreImage.image(from: file("Restore.ipsw"))
            guard let supported = restore.mostFeaturefulSupportedConfiguration else {
                throw VMError("This macOS installer is not supported on this Mac.")
            }
            if needsDisk {
                try supported.hardwareModel.dataRepresentation.write(to: file("HardwareModel"), options: .atomic)
                try VZMacMachineIdentifier().dataRepresentation.write(to: file("MachineIdentifier"), options: .atomic)
                if exists("AuxiliaryStorage") {
                    try manager.removeItem(at: file("AuxiliaryStorage"))
                }
                _ = try VZMacAuxiliaryStorage(creatingStorageAt: file("AuxiliaryStorage"), hardwareModel: supported.hardwareModel, options: [])
                try Data().write(to: file("Installing"), options: .atomic)
                try Data().write(to: file("Disk.img"))
                let disk = try FileHandle(forWritingTo: file("Disk.img"))
                defer { try? disk.close() }
                try disk.truncate(atOffset: 64 * 1024 * 1024 * 1024)
            }
            vm = try makeVM(cpuCount: max(4, supported.minimumSupportedCPUCount), memorySize: max(8 * 1024 * 1024 * 1024, supported.minimumSupportedMemorySize))
            installing = true
            defer { installing = false; window.title = "Mac VM" }
            window.title = "Mac VM — Installing macOS, keep this window open…"
            try await VZMacOSInstaller(virtualMachine: vm!, restoringFromImageAt: file("Restore.ipsw")).install()
            try manager.removeItem(at: file("Installing"))
        }
        if vm == nil { vm = try makeVM() }
        let view = VZVirtualMachineView(frame: window.contentView!.bounds)
        view.autoresizingMask = [.width, .height]
        view.virtualMachine = vm
        view.capturesSystemKeys = true
        window.contentView = view
        try await vm!.start()
        print("VM started."); fflush(stdout)
    }
    func makeVM(cpuCount: Int = 4, memorySize: UInt64 = 8 * 1024 * 1024 * 1024) throws -> VZVirtualMachine {
        let config = VZVirtualMachineConfiguration()
        config.bootLoader = VZMacOSBootLoader()
        config.cpuCount = cpuCount
        config.memorySize = memorySize
        let platform = VZMacPlatformConfiguration()
        guard let model = VZMacHardwareModel(dataRepresentation: try Data(contentsOf: file("HardwareModel"))),
              let identifier = VZMacMachineIdentifier(dataRepresentation: try Data(contentsOf: file("MachineIdentifier"))) else {
            throw VMError("Invalid VM hardware model or machine identifier in \(data.path).")
        }
        platform.hardwareModel = model; platform.machineIdentifier = identifier
        platform.auxiliaryStorage = VZMacAuxiliaryStorage(contentsOf: file("AuxiliaryStorage"))
        config.platform = platform
        config.storageDevices = [VZVirtioBlockDeviceConfiguration(attachment: try VZDiskImageStorageDeviceAttachment(url: file("Disk.img"), readOnly: false))]
        let network = VZVirtioNetworkDeviceConfiguration(); network.attachment = VZNATNetworkDeviceAttachment(); config.networkDevices = [network]
        let graphics = VZMacGraphicsDeviceConfiguration(); graphics.displays = [VZMacGraphicsDisplayConfiguration(widthInPixels: 1920, heightInPixels: 1200, pixelsPerInch: 144)]; config.graphicsDevices = [graphics]
        config.keyboards = [VZUSBKeyboardConfiguration()]; config.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]
        let sound = VZVirtioSoundDeviceConfiguration(); let output = VZVirtioSoundDeviceOutputStreamConfiguration(); output.sink = VZHostAudioOutputStreamSink(); sound.streams = [output]; config.audioDevices = [sound]
        try config.validate()
        let machine = VZVirtualMachine(configuration: config); machine.delegate = self; return machine
    }
    func guestDidStop(_ virtualMachine: VZVirtualMachine) { NSApp.terminate(nil) }
    func virtualMachine(_ virtualMachine: VZVirtualMachine, didStopWithError error: Error) {
        showError(error)
        NSApp.terminate(nil)
    }
    @discardableResult
    func alert(_ title: String, _ message: String, buttons: [String] = ["OK"]) -> NSApplication.ModalResponse {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        for title in buttons { alert.addButton(withTitle: title) }
        return alert.runModal()
    }
    func showError(_ error: Error) { alert("Mac VM could not run", error.localizedDescription) }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        NSApp.terminate(nil)
        return false
    }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard installing || (vm != nil && vm!.state != .stopped) else { return .terminateNow }
        let message = installing ? "Quitting interrupts macOS installation. Reopen the app to retry." : "Shut down macOS inside the VM first to preserve your work."
        return alert("Quit Mac VM?", message, buttons: ["Keep Open", "Quit"]) == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
MainActor.assumeIsolated {
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let menu = NSMenu(); let item = NSMenuItem(); menu.addItem(item); let submenu = NSMenu(); submenu.addItem(withTitle: "Quit Mac VM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"); item.submenu = submenu; app.mainMenu = menu
let controller = Controller(); app.delegate = controller; app.run()
}

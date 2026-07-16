import AppKit
import Foundation

private let serviceLabel = "com.local.c200-keeper"

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var controlWindow: NSWindow?
    private let windowStatus = NSTextField(labelWithString: "Checking auto re-apply…")
    private let statusRow = NSMenuItem(title: "Checking…", action: nil, keyEquivalent: "")
    private let enableItem = NSMenuItem(title: "Enable Auto Re-apply", action: #selector(enableAutoApply), keyEquivalent: "")
    private let disableItem = NSMenuItem(title: "Disable Auto Re-apply", action: #selector(disableAutoApply), keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Use normal app activation so opening from Finder always produces a
        // visible window. The status item remains available in the menu bar.
        NSApp.setActivationPolicy(.regular)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "camera.aperture", accessibilityDescription: "C200 Keeper")
        statusItem.button?.toolTip = "C200 Keeper"

        let menu = NSMenu()
        menu.delegate = self
        statusRow.isEnabled = false
        menu.addItem(statusRow)
        menu.addItem(.separator())
        menu.addItem(item("Save Current Config", #selector(saveCurrent), "s"))
        menu.addItem(item("Apply Saved Config Now", #selector(applyNow), "a"))
        menu.addItem(.separator())
        enableItem.target = self
        disableItem.target = self
        menu.addItem(enableItem)
        menu.addItem(disableItem)
        menu.addItem(.separator())
        menu.addItem(item("Open Instructions", #selector(openInstructions), ""))
        menu.addItem(item("Quit C200 Keeper", #selector(quit), "q"))
        statusItem.menu = menu
        refreshStatus()
        if !ProcessInfo.processInfo.arguments.contains("--login") {
            showControlWindow()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControlWindow()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func item(_ title: String, _ action: Selector, _ key: String) -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    func menuWillOpen(_ menu: NSMenu) { refreshStatus() }

    private var resources: URL { Bundle.main.resourceURL! }
    private var keeperScript: String { resources.appendingPathComponent("c200_keeper.py").path }
    private var python: String {
        let candidates = [
            "/Library/Frameworks/Python.framework/Versions/3.12/bin/python3",
            "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? "/usr/bin/python3"
    }
    private var domain: String { "gui/\(getuid())" }
    private var agentPath: String {
        NSString(string: "~/Library/LaunchAgents/\(serviceLabel).plist").expandingTildeInPath
    }

    @discardableResult
    private func run(_ executable: String, _ arguments: [String]) -> (Int32, String) {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return (process.terminationStatus, String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        } catch {
            return (1, error.localizedDescription)
        }
    }

    private func serviceIsRunning() -> Bool {
        run("/bin/launchctl", ["print", "\(domain)/\(serviceLabel)"]).0 == 0
    }

    private func refreshStatus() {
        let enabled = serviceIsRunning()
        statusRow.title = enabled ? "Auto Re-apply: On" : "Auto Re-apply: Off"
        windowStatus.stringValue = enabled ? "Auto re-apply is ON" : "Auto re-apply is OFF"
        windowStatus.textColor = enabled ? .systemGreen : .secondaryLabelColor
        statusItem.button?.image?.isTemplate = true
        enableItem.isEnabled = !enabled
        disableItem.isEnabled = enabled
    }

    private func showControlWindow() {
        if controlWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 430, height: 320),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "C200 Keeper"
            window.isReleasedWhenClosed = false

            let content = NSView(frame: window.contentView!.bounds)
            content.autoresizingMask = [.width, .height]
            window.contentView = content

            let title = NSTextField(labelWithString: "Anker PowerConf C200 Keeper")
            title.font = .systemFont(ofSize: 20, weight: .semibold)
            title.alignment = .center
            title.frame = NSRect(x: 30, y: 265, width: 370, height: 28)
            content.addSubview(title)

            windowStatus.font = .systemFont(ofSize: 14, weight: .medium)
            windowStatus.alignment = .center
            windowStatus.frame = NSRect(x: 30, y: 232, width: 370, height: 22)
            content.addSubview(windowStatus)

            let help = NSTextField(wrappingLabelWithString: "Set your framing in AnkerWork, close AnkerWork, then save it here.")
            help.alignment = .center
            help.textColor = .secondaryLabelColor
            help.frame = NSRect(x: 45, y: 188, width: 340, height: 38)
            content.addSubview(help)

            addButton("Save Current Config", #selector(saveCurrent), y: 145, to: content)
            addButton("Apply Saved Config Now", #selector(applyNow), y: 105, to: content)
            addButton("Enable Auto Re-apply", #selector(enableAutoApply), y: 65, x: 35, width: 175, to: content)
            addButton("Disable Auto Re-apply", #selector(disableAutoApply), y: 65, x: 220, width: 175, to: content)

            let note = NSTextField(labelWithString: "Closing this window keeps the menu-bar app and background service running.")
            note.font = .systemFont(ofSize: 11)
            note.textColor = .tertiaryLabelColor
            note.alignment = .center
            note.frame = NSRect(x: 20, y: 20, width: 390, height: 18)
            content.addSubview(note)
            controlWindow = window
        }
        refreshStatus()
        NSApp.activate(ignoringOtherApps: true)
        controlWindow?.center()
        controlWindow?.makeKeyAndOrderFront(nil)
    }

    private func addButton(_ title: String, _ action: Selector, y: CGFloat,
                           x: CGFloat = 90, width: CGFloat = 250, to view: NSView) {
        let button = NSButton(title: title, target: self, action: action)
        button.bezelStyle = .rounded
        button.frame = NSRect(x: x, y: y, width: width, height: 32)
        view.addSubview(button)
    }

    private func performKeeper(_ command: String, successTitle: String) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let result = self.run(self.python, [self.keeperScript, command])
            DispatchQueue.main.async {
                self.show(result.0 == 0 ? successTitle : "C200 Keeper Error",
                          result.1.isEmpty ? (result.0 == 0 ? "Done." : "The command failed.") : result.1,
                          isError: result.0 != 0)
                self.refreshStatus()
            }
        }
    }

    @objc private func saveCurrent() {
        performKeeper("capture", successTitle: "Configuration Saved")
    }

    @objc private func applyNow() {
        performKeeper("apply", successTitle: "Configuration Applied")
    }

    @objc private func enableAutoApply() {
        let logs = NSString(string: "~/Library/Logs/C200 Keeper").expandingTildeInPath
        try? FileManager.default.createDirectory(atPath: (agentPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(atPath: logs, withIntermediateDirectories: true)
        let escapedPython = xml(python), escapedScript = xml(keeperScript), escapedLogs = xml(logs)
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0"><dict>
        <key>Label</key><string>\(serviceLabel)</string>
        <key>ProgramArguments</key><array><string>\(escapedPython)</string><string>\(escapedScript)</string><string>run</string></array>
        <key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
        <key>ProcessType</key><string>Background</string>
        <key>StandardOutPath</key><string>\(escapedLogs)/output.log</string>
        <key>StandardErrorPath</key><string>\(escapedLogs)/error.log</string>
        </dict></plist>
        """
        do {
            try plist.write(toFile: agentPath, atomically: true, encoding: .utf8)
            _ = run("/bin/launchctl", ["bootout", "\(domain)/\(serviceLabel)"])
            let result = run("/bin/launchctl", ["bootstrap", domain, agentPath])
            if result.0 == 0 {
                show("Auto Re-apply Enabled", "Your saved camera framing will now be restored automatically.")
            } else {
                show("Could Not Enable", result.1, isError: true)
            }
        } catch { show("Could Not Enable", error.localizedDescription, isError: true) }
        refreshStatus()
    }

    @objc private func disableAutoApply() {
        let result = run("/bin/launchctl", ["bootout", "\(domain)/\(serviceLabel)"])
        if result.0 == 0 {
            show("Auto Re-apply Disabled", "The saved configuration remains available for manual use.")
        } else {
            show("Could Not Disable", result.1, isError: true)
        }
        refreshStatus()
    }

    private func xml(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private func show(_ title: String, _ message: String, isError: Bool = false) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = isError ? .critical : .informational
        alert.runModal()
    }

    @objc private func openInstructions() {
        NSWorkspace.shared.open(resources.appendingPathComponent("README.md"))
    }

    @objc private func quit() { NSApp.terminate(nil) }
}

let application = NSApplication.shared
let applicationDelegate = AppDelegate()
application.delegate = applicationDelegate
application.run()

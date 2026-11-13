import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let wallpaperController = WallpaperController()
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installBundledScreenSaverIfNeeded()
        setupStatusItem()
        wallpaperController.setup()

        wallpaperController.onPlaybackStateChanged = { [weak self] in
            self?.updateMenuItems()
        }

        wallpaperController.onVideoError = { [weak self] message in
            self?.showError(message)
        }
    }

    private func installBundledScreenSaverIfNeeded() {
        guard let bundledURL = Bundle.main.url(forResource: "LoopSaver", withExtension: "saver") else { return }
        let screenSaversDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Screen Savers")
        try? FileManager.default.createDirectory(at: screenSaversDir, withIntermediateDirectories: true)
        let destinationURL = screenSaversDir.appendingPathComponent("LoopSaver.saver")

        var shouldCopy = true
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            let bundledDate = (try? FileManager.default.attributesOfItem(atPath: bundledURL.path)[.modificationDate] as? Date) ?? .distantPast
            let installedDate = (try? FileManager.default.attributesOfItem(atPath: destinationURL.path)[.modificationDate] as? Date) ?? .distantPast
            if installedDate >= bundledDate {
                shouldCopy = false
            }
        }

        if shouldCopy {
            try? FileManager.default.removeItem(at: destinationURL)
            try? FileManager.default.copyItem(at: bundledURL, to: destinationURL)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        wallpaperController.tearDown()
    }

    // MARK: - Status Item

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "play.desktopcomputer", accessibilityDescription: "Loop")
        }
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()

        let chooseItem = NSMenuItem(title: "Choose Video…", action: #selector(chooseVideo), keyEquivalent: "o")
        chooseItem.target = self
        menu.addItem(chooseItem)

        menu.addItem(NSMenuItem.separator())

        let playPause = NSMenuItem(title: wallpaperController.isPlaying ? "Pause" : "Play", action: #selector(togglePlayPause), keyEquivalent: "")
        playPause.target = self
        playPause.tag = 100
        menu.addItem(playPause)

        let mute = NSMenuItem(title: "Mute", action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        mute.state = Settings.shared.isMuted ? .on : .off
        mute.tag = 101
        menu.addItem(mute)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let launchItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchItem.target = self
        launchItem.state = Settings.shared.launchAtLogin ? .on : .off
        launchItem.tag = 102
        menu.addItem(launchItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Loop", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    private func updateMenuItems() {
        guard let menu = statusItem.menu else { return }

        if let playPause = menu.item(withTag: 100) {
            playPause.title = wallpaperController.isPlaying ? "Pause" : "Play"
        }
        if let mute = menu.item(withTag: 101) {
            mute.state = Settings.shared.isMuted ? .on : .off
        }
        if let launch = menu.item(withTag: 102) {
            launch.state = Settings.shared.launchAtLogin ? .on : .off
        }
    }

    // MARK: - Actions

    @objc private func chooseVideo() {
        NSApp.activate(ignoringOtherApps: true)

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Choose a video to use as your wallpaper"

        if panel.runModal() == .OK, let url = panel.url {
            wallpaperController.loadVideo(at: url.path)
        }
    }

    @objc private func togglePlayPause() {
        wallpaperController.togglePlayPause()
    }

    @objc private func toggleMute() {
        wallpaperController.toggleMute()
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            return
        }

        let settingsView = SettingsView(wallpaperController: wallpaperController)
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "Loop Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 440, height: 620))
        window.minSize = NSSize(width: 400, height: 450)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)

        self.settingsWindow = window
    }

    @objc private func toggleLaunchAtLogin() {
        Settings.shared.launchAtLogin.toggle()
        updateMenuItems()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Cannot Play Video"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}


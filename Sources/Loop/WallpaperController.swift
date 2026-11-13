import AppKit
import AVFoundation
import Combine

/// Manages the shared player, looper, wallpaper windows, and playback state.
@MainActor
final class WallpaperController {
    private let settings = Settings.shared
    private let powerMonitor = PowerMonitor()

    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var windows: [WallpaperWindow] = []
    private var cancellables = Set<AnyCancellable>()

    // State flags
    private(set) var userPaused = false
    private var isSleeping = false
    private var isOccluded = false

    var onPlaybackStateChanged: (() -> Void)?

    var isPlaying: Bool {
        player?.rate != 0 && player?.rate != nil
    }

    var hasVideo: Bool {
        settings.videoPath != nil && settings.videoFileExists
    }

    func setup() {
        powerMonitor.start()
        powerMonitor.onPowerStateChanged = { [weak self] in
            self?.updatePlayback()
        }

        registerNotifications()
        observeSettings()

        // Restore last video if available
        if settings.videoFileExists, let path = settings.videoPath {
            loadVideo(at: path)
        }
    }

    func tearDown() {
        powerMonitor.stop()
        removeAllWindows()
        looper = nil
        player?.removeAllItems()
        player = nil
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    // MARK: - Video Loading

    func loadVideo(at path: String) {
        let url = URL(fileURLWithPath: path)
        let asset = AVURLAsset(url: url)

        Task { @MainActor in
            do {
                let isPlayable = try await asset.load(.isPlayable)
                guard isPlayable else {
                    self.onVideoError?("This file format is not supported.\nSupported formats: mp4, mov, m4v (H.264 / HEVC)")
                    return
                }

                self.settings.videoPath = path
                self.setupPlayer(with: asset)
                self.rebuildWindows()
                self.updatePlayback()
                self.updateSystemDesktopImage(for: asset)
            } catch {
                self.onVideoError?("Could not load video: \(error.localizedDescription)")
            }
        }
    }

    var onVideoError: ((String) -> Void)?

    func removeVideo() {
        settings.videoPath = nil
        looper = nil
        player?.removeAllItems()
        player?.pause()
        removeAllWindows()
        onPlaybackStateChanged?()
    }

    private func setupPlayer(with asset: AVAsset) {
        // Tear down existing
        looper = nil
        player?.removeAllItems()

        let item = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(items: [item])
        queuePlayer.isMuted = settings.isMuted
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false
        // Don't set up NowPlaying
        queuePlayer.allowsExternalPlayback = false

        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: AVPlayerItem(asset: asset))

        self.player = queuePlayer
        self.looper = playerLooper
    }

    func updateDesktopImageManually() {
        if let asset = player?.currentItem?.asset {
            updateSystemDesktopImage(for: asset)
        } else if let path = settings.videoPath, FileManager.default.fileExists(atPath: path) {
            let asset = AVURLAsset(url: URL(fileURLWithPath: path))
            updateSystemDesktopImage(for: asset)
        }
    }

    private func updateSystemDesktopImage(for asset: AVAsset) {
        Task.detached(priority: .utility) {
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .positiveInfinity
            generator.requestedTimeToleranceAfter = .positiveInfinity
            let time = CMTime(seconds: 0.1, preferredTimescale: 600)
            guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return }
            let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
            guard let data = bitmapRep.representation(using: .jpeg, properties: [:]) else { return }

            let fileManager = FileManager.default
            let sharedDir = "/Users/Shared/Loop"
            try? fileManager.createDirectory(atPath: sharedDir, withIntermediateDirectories: true, attributes: [
                .posixPermissions: 0o777
            ])

            // Clean up any previous lockscreen poster files so we do not accumulate files
            if let files = try? fileManager.contentsOfDirectory(atPath: sharedDir) {
                for file in files where file.hasPrefix("lockscreen_poster") {
                    try? fileManager.removeItem(atPath: "\(sharedDir)/\(file)")
                }
            }

            // Write with unique timestamp so macOS cache does not prevent refreshing
            let timestamp = Int(Date().timeIntervalSince1970)
            let posterPath = "\(sharedDir)/lockscreen_poster_\(timestamp).jpg"
            let posterURL = URL(fileURLWithPath: posterPath)

            try? data.write(to: posterURL)
            try? fileManager.setAttributes([.posixPermissions: 0o666], ofItemAtPath: posterPath)

            await MainActor.run {
                for screen in NSScreen.screens {
                    let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
                        .imageScaling: NSImageScaling.scaleAxesIndependently.rawValue,
                        .allowClipping: true
                    ]
                    try? NSWorkspace.shared.setDesktopImageURL(posterURL, for: screen, options: options)
                }
            }
        }
    }

    // MARK: - Windows

    func rebuildWindows() {
        removeAllWindows()
        guard hasVideo, player != nil else { return }

        for screen in NSScreen.screens {
            let displayID = screenDisplayID(screen)
            if settings.disabledDisplayIDs.contains(displayID) {
                continue
            }

            let window = WallpaperWindow(screen: screen, displayID: displayID)
            window.updateVideoGravity(settings.scalingMode)
            window.attachPlayer(player)
            window.orderBack(nil)
            windows.append(window)
        }

        updatePlayback()
    }

    private func removeAllWindows() {
        for window in windows {
            window.attachPlayer(nil)
            window.orderOut(nil)
            window.close()
        }
        windows.removeAll()
    }

    func screenDisplayID(_ screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    // MARK: - Playback control

    func togglePlayPause() {
        userPaused.toggle()
        updatePlayback()
        onPlaybackStateChanged?()
    }

    func toggleMute() {
        settings.isMuted.toggle()
        player?.isMuted = settings.isMuted
        onPlaybackStateChanged?()
    }

    func setScalingMode(_ mode: ScalingMode) {
        settings.scalingMode = mode
        for window in windows {
            window.updateVideoGravity(mode)
        }
    }

    func updatePlayback() {
        guard let player = player, hasVideo, !windows.isEmpty else {
            player?.pause()
            onPlaybackStateChanged?()
            return
        }

        let isBatteryLow: Bool
        if settings.pauseOnBattery && powerMonitor.isOnBattery {
            let currentLevel = powerMonitor.batteryPercentage ?? 100
            isBatteryLow = currentLevel <= settings.batteryThreshold
        } else {
            isBatteryLow = false
        }

        let shouldPause = userPaused
            || isSleeping
            || isOccluded
            || isBatteryLow

        if shouldPause {
            player.pause()
        } else {
            player.play()
        }
        onPlaybackStateChanged?()
    }

    // MARK: - Notifications

    private func registerNotifications() {
        let nc = NotificationCenter.default
        let wsnc = NSWorkspace.shared.notificationCenter

        nc.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )

        // Occlusion detection on each window — we observe globally
        nc.addObserver(
            self,
            selector: #selector(occlusionChanged),
            name: NSWindow.didChangeOcclusionStateNotification,
            object: nil
        )

        wsnc.addObserver(
            self,
            selector: #selector(willSleep),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(screensDidSleep),
            name: NSWorkspace.screensDidSleepNotification,
            object: nil
        )
        wsnc.addObserver(
            self,
            selector: #selector(screensDidWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    @objc private func screenParametersChanged(_ notification: Notification) {
        rebuildWindows()
    }

    @objc private func occlusionChanged(_ notification: Notification) {
        // Check if ANY wallpaper window is visible
        let anyVisible = windows.contains { $0.occlusionState.contains(.visible) }
        isOccluded = !anyVisible
        updatePlayback()
    }

    @objc private func willSleep(_ notification: Notification) {
        isSleeping = true
        updatePlayback()
    }

    @objc private func didWake(_ notification: Notification) {
        isSleeping = false
        updatePlayback()
    }

    @objc private func screensDidSleep(_ notification: Notification) {
        isSleeping = true
        updatePlayback()
    }

    @objc private func screensDidWake(_ notification: Notification) {
        isSleeping = false
        updatePlayback()
    }

    // MARK: - Settings observation

    private func observeSettings() {
        settings.$scalingMode
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] mode in
                self?.setScalingMode(mode)
            }
            .store(in: &cancellables)

        settings.$isMuted
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] muted in
                self?.player?.isMuted = muted
            }
            .store(in: &cancellables)

        settings.$pauseOnBattery
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePlayback()
            }
            .store(in: &cancellables)

        settings.$batteryThreshold
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updatePlayback()
            }
            .store(in: &cancellables)

        settings.$disabledDisplayIDs
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.rebuildWindows()
            }
            .store(in: &cancellables)
    }

    /// Expose the player for the settings preview
    var currentPlayer: AVQueuePlayer? { player }

    /// Current battery info
    var currentBatteryPercentage: Int? { powerMonitor.batteryPercentage }
    var isOnBattery: Bool { powerMonitor.isOnBattery }
}


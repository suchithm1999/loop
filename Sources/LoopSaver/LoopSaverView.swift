import ScreenSaver
import AVFoundation
import AppKit

/// LoopSaver — a macOS screensaver that plays the video selected in the Loop app.
/// It reads configuration from ScreenSaverDefaults ("com.example.loop.saver")
/// and the shared directory at /Users/Shared/Loop.
@objc(LoopSaverView)
final class LoopSaverView: ScreenSaverView {

    // MARK: - Player state

    private var player: AVQueuePlayer?
    private var playerLayer: AVPlayerLayer?
    private var looper: AVPlayerLooper?
    private var messageLayer: CATextLayer?
    private var currentLoadedPath: String?
    private var frameCheckCount: Int = 0

    // MARK: - Init

    override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        self.animationTimeInterval = 1.0 / 30.0
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.cgColor
    }

    // MARK: - Lifecycle

    override func startAnimation() {
        super.startAnimation()
        setupPlayerIfNeeded()
        player?.play()
    }

    override func stopAnimation() {
        super.stopAnimation()
        player?.pause()
    }

    override func draw(_ rect: NSRect) {
        NSColor.black.setFill()
        rect.fill()
    }

    override func animateOneFrame() {
        // Periodically (every 2 seconds / 60 frames) check if the user chose a new video in Loop
        frameCheckCount += 1
        if frameCheckCount >= 60 {
            frameCheckCount = 0
            if let latestPath = readVideoPath(), latestPath != currentLoadedPath {
                setupPlayerIfNeeded()
            }
        }
    }

    override func resize(withOldSuperviewSize oldSize: NSSize) {
        super.resize(withOldSuperviewSize: oldSize)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer?.frame = bounds
        messageLayer?.frame = bounds
        CATransaction.commit()
    }

    override var hasConfigureSheet: Bool { false }
    override var configureSheet: NSWindow? { nil }

    // MARK: - Player setup

    private func setupPlayerIfNeeded() {
        // Read current video path from shared configurations
        guard let videoPath = readVideoPath(),
              FileManager.default.fileExists(atPath: videoPath) else {
            tearDownPlayer()
            showMessage("No video selected in Loop.\nOpen Loop from the menu bar and choose a video.")
            return
        }

        // If player is already running with the exact same video file, keep playing
        if let player = player, currentLoadedPath == videoPath {
            player.play()
            return
        }

        // Otherwise, rebuild player with the new video file
        tearDownPlayer()
        currentLoadedPath = videoPath

        let scalingMode = readScalingMode()
        let url = URL(fileURLWithPath: videoPath)
        let asset = AVURLAsset(url: url)
        let templateItem = AVPlayerItem(asset: asset)
        let queuePlayer = AVQueuePlayer(items: [AVPlayerItem(asset: asset)])

        queuePlayer.isMuted = true
        queuePlayer.allowsExternalPlayback = false
        queuePlayer.preventsDisplaySleepDuringVideoPlayback = false

        let playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: templateItem)

        self.player = queuePlayer
        self.looper = playerLooper

        let layer = AVPlayerLayer(player: queuePlayer)
        layer.frame = bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]

        switch scalingMode {
        case "fit":
            layer.videoGravity = .resizeAspect
        case "stretch":
            layer.videoGravity = .resize
        default:
            layer.videoGravity = .resizeAspectFill
        }

        self.layer?.addSublayer(layer)
        self.playerLayer = layer

        queuePlayer.play()
    }

    private func tearDownPlayer() {
        player?.pause()
        looper = nil
        player?.removeAllItems()
        player = nil
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        currentLoadedPath = nil
        removeMessage()
    }

    // MARK: - Shared settings retrieval

    private func readVideoPath() -> String? {
        // 1. Try ScreenSaverDefaults (Apple's official screensaver IPC preference system)
        if let defaults = ScreenSaverDefaults(forModuleWithName: "com.example.loop.saver") {
            defaults.synchronize()
            if let path = defaults.string(forKey: "videoPath"),
               FileManager.default.fileExists(atPath: path) {
                return path
            }
        }

        // 2. Try shared video location in /Users/Shared/Loop/current_video.mp4
        let sharedVideoPath = "/Users/Shared/Loop/current_video.mp4"
        if FileManager.default.fileExists(atPath: sharedVideoPath) {
            return sharedVideoPath
        }

        // 3. Try /Users/Shared/Loop/config.json
        let configPath = "/Users/Shared/Loop/config.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let path = json["videoPath"] as? String,
           FileManager.default.fileExists(atPath: path) {
            return path
        }

        // 4. Try standard suite defaults fallback
        if let defaults = UserDefaults(suiteName: "com.example.loop"),
           let path = defaults.string(forKey: "videoPath"),
           FileManager.default.fileExists(atPath: path) {
            return path
        }

        return nil
    }

    private func readScalingMode() -> String {
        if let defaults = ScreenSaverDefaults(forModuleWithName: "com.example.loop.saver") {
            defaults.synchronize()
            if let mode = defaults.string(forKey: "scalingMode") {
                return mode
            }
        }

        let configPath = "/Users/Shared/Loop/config.json"
        if let data = try? Data(contentsOf: URL(fileURLWithPath: configPath)),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let mode = json["scalingMode"] as? String {
            return mode
        }

        return "fill"
    }

    // MARK: - Message overlay

    private func showMessage(_ text: String) {
        removeMessage()
        let textLayer = CATextLayer()
        textLayer.string = text
        textLayer.fontSize = isPreview ? 12 : 20
        textLayer.foregroundColor = NSColor.white.withAlphaComponent(0.75).cgColor
        textLayer.alignmentMode = .center
        textLayer.frame = bounds.insetBy(dx: 20, dy: 40)
        textLayer.contentsScale = NSScreen.main?.backingScaleFactor ?? 2.0
        textLayer.isWrapped = true
        textLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        self.layer?.addSublayer(textLayer)
        self.messageLayer = textLayer
    }

    private func removeMessage() {
        messageLayer?.removeFromSuperlayer()
        messageLayer = nil
    }
}

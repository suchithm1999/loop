import AppKit
import AVFoundation
import QuartzCore

/// A borderless wallpaper window with an AVPlayerLayer.
@MainActor
final class WallpaperWindow: NSWindow {
    let playerLayer = AVPlayerLayer()
    let displayID: CGDirectDisplayID

    init(screen: NSScreen, displayID: CGDirectDisplayID) {
        self.displayID = displayID
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )

        // Window configuration
        self.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.ignoresMouseEvents = true
        self.hasShadow = false
        self.isOpaque = true
        self.backgroundColor = .black
        self.isReleasedWhenClosed = false

        // Layer-backed content view
        let contentView = NSView(frame: screen.frame)
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.black.cgColor

        // Player layer
        playerLayer.frame = contentView.bounds
        playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        playerLayer.videoGravity = .resizeAspectFill
        contentView.layer?.addSublayer(playerLayer)

        self.contentView = contentView
        self.setFrame(screen.frame, display: true)
    }

    func updateVideoGravity(_ mode: ScalingMode) {
        switch mode {
        case .fill:
            playerLayer.videoGravity = .resizeAspectFill
        case .fit:
            playerLayer.videoGravity = .resizeAspect
        case .stretch:
            playerLayer.videoGravity = .resize
        }
    }

    func attachPlayer(_ player: AVQueuePlayer?) {
        playerLayer.player = player
    }
}


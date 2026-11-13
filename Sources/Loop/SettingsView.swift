import SwiftUI
import AVFoundation
import AVKit
import AppKit

/// ViewModel to hold mutable state for the settings view, avoiding @State macro issues.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var syncNotice: String?
}

struct SettingsView: View {
    @ObservedObject var settings = Settings.shared
    @ObservedObject var viewModel = SettingsViewModel()
    var wallpaperController: WallpaperController?

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
                Text("Loop Settings")
                    .font(.title2)
                    .fontWeight(.semibold)

                Divider()

                // Video section
                GroupBox("Video") {
                    VStack(alignment: .leading, spacing: 10) {
                        if let fileName = settings.videoFileName {
                            if settings.videoFileExists {
                                HStack {
                                    Image(systemName: "film")
                                    Text(fileName)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    Spacer()
                                }

                                // Preview
                                if let player = wallpaperController?.currentPlayer {
                                    VideoPreview(player: player)
                                        .frame(height: 160)
                                        .cornerRadius(8)
                                        .clipped()
                                }
                            } else {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                    Text("File not found: \(fileName)")
                                        .foregroundColor(.secondary)
                                }
                            }
                        } else {
                            Text("No video selected")
                                .foregroundColor(.secondary)
                        }

                        HStack {
                            Button("Choose Video…") {
                                chooseVideo()
                            }
                            if settings.videoPath != nil {
                                Button("Remove Video") {
                                    wallpaperController?.removeVideo()
                                }
                            }
                        }

                        if let error = viewModel.errorMessage {
                            Text(error)
                                .foregroundColor(.red)
                                .font(.caption)
                        }

                        Text("Supported: mp4, mov, m4v (H.264 / HEVC)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(4)
                }

                // Playback settings
                GroupBox("Playback") {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("Scaling", selection: $settings.scalingMode) {
                            ForEach(ScalingMode.allCases) { mode in
                                Text(mode.displayName).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        Toggle("Mute audio", isOn: $settings.isMuted)
                        Toggle("Launch at login", isOn: $settings.launchAtLogin)

                        Divider()

                        // Battery smart pause
                        Toggle("Pause on battery power", isOn: $settings.pauseOnBattery)

                        if settings.pauseOnBattery {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("Pause threshold:")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(settings.batteryThreshold >= 100 ? "Always when unplugged" : "Below \(settings.batteryThreshold)% battery")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.primary)
                                }

                                Slider(
                                    value: Binding(
                                        get: { Double(settings.batteryThreshold) },
                                        set: { settings.batteryThreshold = Int($0) }
                                    ),
                                    in: 5...100,
                                    step: 5
                                )

                                HStack {
                                    Text("5% (low)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("20% (recommended)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("100% (any)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }

                                if let percent = wallpaperController?.currentBatteryPercentage {
                                    HStack(spacing: 5) {
                                        Image(systemName: wallpaperController?.isOnBattery == true ? "battery.50" : "battery.100.bolt")
                                            .foregroundColor(wallpaperController?.isOnBattery == true ? .orange : .green)
                                        Text("Current Battery: \(percent)% (\(wallpaperController?.isOnBattery == true ? "On Battery" : "Connected to Power"))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.leading, 12)
                            .padding(.vertical, 2)
                        }
                    }
                    .padding(4)
                }

                // Displays
                GroupBox("Displays") {
                    VStack(alignment: .leading, spacing: 6) {
                        let screens = NSScreen.screens
                        if screens.isEmpty {
                            Text("No displays detected")
                                .foregroundColor(.secondary)
                        } else {
                            ForEach(Array(screens.enumerated()), id: \.offset) { index, screen in
                                let displayID = displayIDFor(screen)
                                let isEnabled = !settings.disabledDisplayIDs.contains(displayID)
                                Toggle(displayName(for: screen, index: index), isOn: Binding(
                                    get: { isEnabled },
                                    set: { enabled in
                                        if enabled {
                                            settings.disabledDisplayIDs.remove(displayID)
                                        } else {
                                            settings.disabledDisplayIDs.insert(displayID)
                                        }
                                    }
                                ))
                            }
                        }
                    }
                    .padding(4)
                }

                // Lock Screen & Screen Saver
                GroupBox("Lock Screen & Screen Saver") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("On macOS, third-party apps cannot inject animated code directly into the secure login/lock window. Loop handles this with two complementary features:")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top) {
                                Image(systemName: "lock.desktopcomputer")
                                    .foregroundColor(.blue)
                                VStack(alignment: .leading) {
                                    Text("Lock Screen Background")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text("A matching high-res poster frame is automatically applied as your system desktop image so the Lock Screen displays your video's visual.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack(alignment: .top) {
                                Image(systemName: "play.rectangle.on.rectangle")
                                    .foregroundColor(.purple)
                                VStack(alignment: .leading) {
                                    Text("LoopSaver Screensaver")
                                        .font(.caption)
                                        .fontWeight(.semibold)
                                    Text("Plays the full live video on seamless loop when your screen saver activates or when idle.")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 2)

                        if settings.videoFileExists {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Video synced to LoopSaver & Lock Screen")
                                    .font(.caption)
                                    .foregroundColor(.primary)
                            }
                        } else {
                            HStack {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                                Text("Choose a video above to sync with screensaver & lock screen")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }

                        HStack(spacing: 8) {
                            Button("Test Screen Saver Now") {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app"))
                            }

                            Button("Re-Sync Video Now") {
                                settings.syncToScreenSaver()
                                wallpaperController?.updateDesktopImageManually()
                                viewModel.syncNotice = "Synced video & lock screen poster frame!"
                            }
                        }

                        HStack(spacing: 8) {
                            Button("Open Lock Screen Settings…") {
                                openSettingsPane("x-apple.systempreferences:com.apple.LockScreen-Settings.extension")
                            }

                            Button("Open Wallpaper Settings…") {
                                openSettingsPane("x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")
                            }
                        }

                        if let notice = viewModel.syncNotice {
                            Text(notice)
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                    }
                    .padding(4)
                }

                Spacer(minLength: 16)
            }
            .padding(20)
        }
        .frame(width: 440)
        .frame(minHeight: 520, maxHeight: 720)
    }

    private func openSettingsPane(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    private func chooseVideo() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]
        panel.message = "Choose a video to use as your wallpaper"

        let vm = viewModel
        if panel.runModal() == .OK, let url = panel.url {
            vm.errorMessage = nil
            vm.syncNotice = nil
            wallpaperController?.onVideoError = { msg in
                vm.errorMessage = msg
            }
            wallpaperController?.loadVideo(at: url.path)
        }
    }

    private func displayIDFor(_ screen: NSScreen) -> CGDirectDisplayID {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return screen.deviceDescription[key] as? CGDirectDisplayID ?? 0
    }

    private func displayName(for screen: NSScreen, index: Int) -> String {
        let name = screen.localizedName
        let res = "\(Int(screen.frame.width))×\(Int(screen.frame.height))"
        return "Display \(index + 1): \(name) (\(res))"
    }
}

/// A simple preview showing the current video via AVPlayerLayer
struct VideoPreview: NSViewRepresentable {
    let player: AVQueuePlayer

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        view.layer?.addSublayer(layer)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let layer = nsView.layer?.sublayers?.first as? AVPlayerLayer {
            layer.frame = nsView.bounds
        }
    }
}

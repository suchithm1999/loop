import Foundation
import Combine
import ServiceManagement
import ScreenSaver

/// Persisted settings backed by UserDefaults and synced to LoopSaver screensaver.
@MainActor
final class Settings: ObservableObject {
    static let shared = Settings()

    private let defaults = UserDefaults.standard

    private enum Key: String {
        case videoPath
        case isMuted
        case scalingMode
        case pauseOnBattery
        case batteryThreshold
        case launchAtLogin
        case disabledDisplayIDs
    }

    @Published var videoPath: String? {
        didSet {
            defaults.set(videoPath, forKey: Key.videoPath.rawValue)
            defaults.synchronize()
            syncToScreenSaver()
        }
    }
    @Published var isMuted: Bool {
        didSet {
            defaults.set(isMuted, forKey: Key.isMuted.rawValue)
            defaults.synchronize()
        }
    }
    @Published var scalingMode: ScalingMode {
        didSet {
            defaults.set(scalingMode.rawValue, forKey: Key.scalingMode.rawValue)
            defaults.synchronize()
            syncToScreenSaver()
        }
    }
    @Published var pauseOnBattery: Bool {
        didSet { defaults.set(pauseOnBattery, forKey: Key.pauseOnBattery.rawValue) }
    }
    /// Battery level percentage threshold below which playback pauses on battery (e.g. 20%).
    /// Set to 100 to pause whenever running on battery.
    @Published var batteryThreshold: Int {
        didSet {
            defaults.set(batteryThreshold, forKey: Key.batteryThreshold.rawValue)
            defaults.synchronize()
        }
    }
    @Published var launchAtLogin: Bool {
        didSet {
            defaults.set(launchAtLogin, forKey: Key.launchAtLogin.rawValue)
            updateLoginItem()
        }
    }

    /// Set of CGDirectDisplayID values that are disabled
    @Published var disabledDisplayIDs: Set<UInt32> {
        didSet {
            let arr = Array(disabledDisplayIDs)
            defaults.set(arr, forKey: Key.disabledDisplayIDs.rawValue)
        }
    }

    /// Whether the last video path points to an existing file
    var videoFileExists: Bool {
        guard let path = videoPath else { return false }
        return FileManager.default.fileExists(atPath: path)
    }

    var videoFileName: String? {
        guard let path = videoPath else { return nil }
        return (path as NSString).lastPathComponent
    }

    private init() {
        self.videoPath = defaults.string(forKey: Key.videoPath.rawValue)
        self.isMuted = defaults.object(forKey: Key.isMuted.rawValue) as? Bool ?? true
        let modeRaw = defaults.string(forKey: Key.scalingMode.rawValue) ?? ScalingMode.fill.rawValue
        self.scalingMode = ScalingMode(rawValue: modeRaw) ?? .fill
        self.pauseOnBattery = defaults.object(forKey: Key.pauseOnBattery.rawValue) as? Bool ?? true
        self.batteryThreshold = defaults.object(forKey: Key.batteryThreshold.rawValue) as? Int ?? 20
        self.launchAtLogin = defaults.bool(forKey: Key.launchAtLogin.rawValue)
        let ids = defaults.array(forKey: Key.disabledDisplayIDs.rawValue) as? [UInt32] ?? []
        self.disabledDisplayIDs = Set(ids)

        // Sync to screensaver on launch
        syncToScreenSaver()
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Login item error: \(error)")
        }
    }

    /// Synchronizes the selected video and scaling mode to LoopSaver screensaver
    /// via ScreenSaverDefaults and universal shared directory (/Users/Shared/Loop).
    func syncToScreenSaver() {
        guard let path = videoPath, FileManager.default.fileExists(atPath: path) else {
            // Clean up screensaver configuration
            if let saverDefaults = ScreenSaverDefaults(forModuleWithName: "com.example.loop.saver") {
                saverDefaults.removeObject(forKey: "videoPath")
                saverDefaults.synchronize()
            }
            try? FileManager.default.removeItem(atPath: "/Users/Shared/Loop/current_video.mp4")
            try? FileManager.default.removeItem(atPath: "/Users/Shared/Loop/config.json")
            return
        }

        let sharedDir = URL(fileURLWithPath: "/Users/Shared/Loop")
        try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true, attributes: [
            .posixPermissions: 0o777
        ])

        let sharedVideoURL = sharedDir.appendingPathComponent("current_video.mp4")
        let sourceURL = URL(fileURLWithPath: path)

        // Copy video to shared folder so ScreenSaverEngine/legacyScreenSaver
        // can access it even if source folder has restricted TCC permissions
        try? FileManager.default.removeItem(at: sharedVideoURL)
        do {
            try FileManager.default.copyItem(at: sourceURL, to: sharedVideoURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: sharedVideoURL.path)
        } catch {
            print("Could not copy video to shared folder: \(error)")
        }

        let effectiveVideoPath = FileManager.default.fileExists(atPath: sharedVideoURL.path) ? sharedVideoURL.path : path

        // 1. Write to ScreenSaverDefaults
        if let saverDefaults = ScreenSaverDefaults(forModuleWithName: "com.example.loop.saver") {
            saverDefaults.set(effectiveVideoPath, forKey: "videoPath")
            saverDefaults.set(scalingMode.rawValue, forKey: "scalingMode")
            saverDefaults.set(Date().timeIntervalSince1970, forKey: "updatedAt")
            saverDefaults.synchronize()
        }

        // 2. Write fallback JSON configuration
        let configURL = sharedDir.appendingPathComponent("config.json")
        let config: [String: Any] = [
            "videoPath": effectiveVideoPath,
            "originalPath": path,
            "scalingMode": scalingMode.rawValue,
            "updatedAt": Date().timeIntervalSince1970
        ]
        if let data = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) {
            try? data.write(to: configURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o666], ofItemAtPath: configURL.path)
        }

        // 3. Ensure LoopSaver is configured as the active macOS screensaver
        makeDefaultScreenSaver()
    }

    /// Sets LoopSaver as the active macOS screensaver in system preferences.
    func makeDefaultScreenSaver() {
        let saverPath = NSString(string: "~/Library/Screen Savers/LoopSaver.saver").expandingTildeInPath
        guard FileManager.default.fileExists(atPath: saverPath) else { return }

        let dict: [String: Any] = [
            "moduleName": "LoopSaver",
            "path": saverPath,
            "type": 0
        ]
        CFPreferencesSetValue("moduleDict" as CFString, dict as CFPropertyList, "com.apple.screensaver" as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)

        let currentIdle = CFPreferencesCopyValue("idleTime" as CFString, "com.apple.screensaver" as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int ?? 0
        if currentIdle == 0 {
            // Enable screensaver if it was disabled (default to 2 minutes)
            CFPreferencesSetValue("idleTime" as CFString, 120 as CFPropertyList, "com.apple.screensaver" as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        CFPreferencesSynchronize("com.apple.screensaver" as CFString, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
}

enum ScalingMode: String, CaseIterable, Identifiable {
    case fill = "fill"
    case fit = "fit"
    case stretch = "stretch"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fill: return "Fill"
        case .fit: return "Fit"
        case .stretch: return "Stretch"
        }
    }

    var videoGravity: String {
        switch self {
        case .fill: return "resizeAspectFill"
        case .fit: return "resizeAspect"
        case .stretch: return "resize"
        }
    }
}

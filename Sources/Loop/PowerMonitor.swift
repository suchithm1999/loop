import Foundation
import IOKit.ps

/// Monitors AC vs battery power state and current battery charge percentage.
@MainActor
final class PowerMonitor: ObservableObject {
    private var timer: Timer?
    private var runLoopSource: CFRunLoopSource?
    var onPowerStateChanged: (() -> Void)?

    @Published private(set) var isOnBattery: Bool = false
    @Published private(set) var batteryPercentage: Int? = nil

    func start() {
        refresh()

        // 1. Event-driven notification when power source switches (AC vs Battery)
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context = context else { return }
            let monitor = Unmanaged<PowerMonitor>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in
                monitor.refresh()
            }
        }, Unmanaged.passUnretained(self).toOpaque())

        if let source = source?.takeRetainedValue() {
            self.runLoopSource = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        }

        // 2. Periodic 15-second timer to monitor gradual battery percentage drop
        timer = Timer.scheduledTimer(withTimeInterval: 15.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil

        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = nil
        }
    }

    func refresh() {
        let (batteryMode, percentage) = Self.readPowerInfo()
        let changed = (batteryMode != isOnBattery) || (percentage != batteryPercentage)

        isOnBattery = batteryMode
        batteryPercentage = percentage

        if changed {
            onPowerStateChanged?()
        }
    }

    static func readPowerInfo() -> (isOnBattery: Bool, percentage: Int?) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              !sources.isEmpty else {
            // Desktop Mac without battery or power info unavailable
            return (false, nil)
        }

        var isBattery = false
        if let type = IOPSGetProvidingPowerSourceType(snapshot)?.takeRetainedValue() as String? {
            isBattery = (type == kIOPSBatteryPowerValue)
        }

        var batteryPercent: Int? = nil
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            if let isPresent = desc[kIOPSIsPresentKey] as? Bool, !isPresent {
                continue
            }
            if let current = desc[kIOPSCurrentCapacityKey] as? Int,
               let max = desc[kIOPSMaxCapacityKey] as? Int, max > 0 {
                batteryPercent = Int((Double(current) / Double(max)) * 100.0)
                break
            }
        }

        return (isBattery, batteryPercent)
    }
}

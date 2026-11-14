import Foundation
import NetworkExtension
import Network
import CoreLocation
import BackgroundTasks

struct Entry: Codable, Hashable {
    var day: String; var kind: String; var ssid: String
    var down: UInt64; var up: UInt64
}
struct State: Codable {
    var entries: [Entry] = []
    var last: [String: UInt64]? = nil
    var lastSSID: String = "Wi-Fi"
}

enum Interfaces {
    static func read() -> [String: UInt64] {
        var r: [String: UInt64] = ["wi": 0, "wo": 0, "ci": 0, "co": 0]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return r }
        defer { freeifaddrs(ifaddr) }
        var ptr = first
        while true {
            let i = ptr.pointee
            if let a = i.ifa_addr, a.pointee.sa_family == UInt8(AF_LINK), let d = i.ifa_data {
                let name = String(cString: i.ifa_name)
                let data = d.assumingMemoryBound(to: if_data.self).pointee
                if name == "en0" {
                    r["wi"]! += UInt64(data.ifi_ibytes); r["wo"]! += UInt64(data.ifi_obytes)
                } else if name.hasPrefix("pdp_ip") {
                    r["ci"]! += UInt64(data.ifi_ibytes); r["co"]! += UInt64(data.ifi_obytes)
                }
            }
            guard let n = i.ifa_next else { break }
            ptr = n
        }
        return r
    }
}

final class Store: ObservableObject {
    static let shared = Store()
    @Published var state = State()
    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("usage.json")
    private let monitor = NWPathMonitor()

    var entries: [Entry] { state.entries }

    init() {
        if let d = try? Data(contentsOf: url), let s = try? JSONDecoder().decode(State.self, from: d) { state = s }
        monitor.pathUpdateHandler = { [weak self] _ in DispatchQueue.main.async { self?.tick() } }
        monitor.start(queue: .global())
    }

    static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    private func delta(_ c: UInt64, _ l: UInt64) -> UInt64 {
        if c >= l { return c - l }
        if l > 3_000_000_000 { return c + 4_294_967_296 - l } // التفاف 32 بت
        return c // إعادة تشغيل الجهاز
    }

    private func add(_ kind: String, _ ssid: String, _ down: UInt64, _ up: UInt64) {
        guard down > 0 || up > 0 else { return }
        let day = Store.dayString(Date())
        if let i = state.entries.firstIndex(where: { $0.day == day && $0.kind == kind && $0.ssid == ssid }) {
            state.entries[i].down += down; state.entries[i].up += up
        } else {
            state.entries.append(Entry(day: day, kind: kind, ssid: ssid, down: down, up: up))
        }
    }

    func tick(_ done: (() -> Void)? = nil) {
        let cur = Interfaces.read()
        if let l = state.last {
            add("wifi", state.lastSSID, delta(cur["wi"]!, l["wi"]!), delta(cur["wo"]!, l["wo"]!))
            add("cell", "SIM", delta(cur["ci"]!, l["ci"]!), delta(cur["co"]!, l["co"]!))
        }
        state.last = cur
        save()
        NEHotspotNetwork.fetchCurrent { n in
            DispatchQueue.main.async {
                self.state.lastSSID = n?.ssid ?? "Wi-Fi"
                self.save(); done?()
            }
        }
    }

    func save() {
        if let d = try? JSONEncoder().encode(state) { try? d.write(to: url, options: .atomic) }
    }
}

final class Loc: NSObject, CLLocationManagerDelegate {
    static let shared = Loc()
    private let m = CLLocationManager()
    func start() {
        m.delegate = self
        m.requestWhenInUseAuthorization()
        m.requestAlwaysAuthorization()
        m.startMonitoringSignificantLocationChanges()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        DispatchQueue.main.async { Store.shared.tick() }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { Store.shared.tick() }
    }
}

enum Scheduler {
    static func schedule() {
        let r = BGAppRefreshTaskRequest(identifier: "com.datapulse.refresh")
        r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        try? BGTaskScheduler.shared.submit(r)
    }
}

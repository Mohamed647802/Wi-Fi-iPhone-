import Foundation
import NetworkExtension
import CoreLocation

struct UsageEntry: Codable, Hashable {
    var day: String
    var kind: String
    var ssid: String
    var down: UInt64
    var up: UInt64
}

struct AppState: Codable {
    var entries: [UsageEntry] = []
    var last: [String: UInt64]? = nil
    var days: [DayUsage] = []
    var apps: [AppUsage] = []

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([UsageEntry].self, forKey: .entries) ?? []
        last = try c.decodeIfPresent([String: UInt64].self, forKey: .last)
        days = try c.decodeIfPresent([DayUsage].self, forKey: .days) ?? []
        apps = try c.decodeIfPresent([AppUsage].self, forKey: .apps) ?? []
    }
}

enum Interfaces {
    // عدّادات النظام الحقيقية (تراكمية منذ آخر إقلاع للجهاز)
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
                    r["wi"]! += UInt64(data.ifi_ibytes)
                    r["wo"]! += UInt64(data.ifi_obytes)
                } else if name.hasPrefix("pdp_ip") {
                    r["ci"]! += UInt64(data.ifi_ibytes)
                    r["co"]! += UInt64(data.ifi_obytes)
                }
            }
            guard let n = i.ifa_next else { break }
            ptr = n
        }
        return r
    }

    static func bootDate() -> Date {
        var tv = timeval()
        var size = MemoryLayout<timeval>.stride
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        if sysctl(&mib, 2, &tv, &size, nil, 0) == 0 {
            return Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
        }
        return Date()
    }
}

final class Store: ObservableObject {
    static let shared = Store()
    @Published var state = AppState()
    @Published var refreshing = false
    @Published var lastUpdate: Date? = nil
    @Published var dbStatus = ""
    @Published var dbAvailable = false

    private let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("usage.json")

    var entries: [UsageEntry] { state.entries }

    init() {
        if let d = try? Data(contentsOf: url),
           let s = try? JSONDecoder().decode(AppState.self, from: d) {
            state = s
        }
    }

    static func dayString(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: d)
    }

    private func delta(_ c: UInt64, _ l: UInt64) -> UInt64 {
        if c >= l { return c - l }
        if l > 3_000_000_000 { return c + 4_294_967_296 - l } // التفاف 32 بت
        return c // إعادة تشغيل الجهاز: الاستهلاك منذ الإقلاع
    }

    private func add(_ day: String, _ kind: String, _ ssid: String, _ down: UInt64, _ up: UInt64) {
        guard down > 0 || up > 0 else { return }
        if let i = state.entries.firstIndex(where: { $0.day == day && $0.kind == kind && $0.ssid == ssid }) {
            state.entries[i].down += down
            state.entries[i].up += up
        } else {
            state.entries.append(UsageEntry(day: day, kind: kind, ssid: ssid, down: down, up: up))
        }
    }

    func addManual(day: Date, bytes: UInt64) {
        add(Store.dayString(day), "cell", "إدخال يدوي", bytes, 0)
        save()
    }

    // يُستدعى عند فتح التطبيق أو التحديث اليدوي
    func refresh(_ done: (() -> Void)? = nil) {
        refreshing = true
        let cur = Interfaces.read()
        NEHotspotNetwork.fetchCurrent { n in
            DispatchQueue.main.async {
                let ssid = n?.ssid ?? "Wi-Fi"
                let today = Store.dayString(Date())
                if let l = self.state.last {
                    self.add(today, "wifi", ssid,
                             self.delta(cur["wi"]!, l["wi"]!), self.delta(cur["wo"]!, l["wo"]!))
                    self.add(today, "cell", "SIM",
                             self.delta(cur["ci"]!, l["ci"]!), self.delta(cur["co"]!, l["co"]!))
                } else {
                    let boot = Store.dayString(Interfaces.bootDate())
                    self.add(boot, "wifi", "منذ تشغيل الجهاز", cur["wi"]!, cur["wo"]!)
                    self.add(boot, "cell", "SIM", cur["ci"]!, cur["co"]!)
                }
                self.state.last = cur
                self.save()
                self.loadSystemLog(done)
            }
        }
    }

    // قراءة سجل النظام (الأيام السابقة + التطبيقات) إن كانت الصلاحيات متاحة
    private func loadSystemLog(_ done: (() -> Void)?) {
        DispatchQueue.global(qos: .userInitiated).async {
            let (res, msg) = UsageDB.load()
            DispatchQueue.main.async {
                if let r = res {
                    self.merge(r)
                    self.dbAvailable = true
                    self.dbStatus = r.report
                } else {
                    self.dbAvailable = false
                    self.dbStatus = msg
                }
                self.lastUpdate = Date()
                self.refreshing = false
                self.save()
                done?()
            }
        }
    }

    // دمج مع الأرشيف الداخلي: لا نستبدل يوماً بقيمة أصغر (حماية من تصفير النظام لسجله)
    private func merge(_ r: DBResult) {
        var dayMap: [String: DayUsage] = [:]
        for d in state.days { dayMap[d.day] = d }
        for n in r.days {
            if let old = dayMap[n.day] {
                let oldTotal = old.wifiDown + old.wifiUp + old.cellDown + old.cellUp
                let newTotal = n.wifiDown + n.wifiUp + n.cellDown + n.cellUp
                if oldTotal > newTotal { continue }
            }
            dayMap[n.day] = n
        }
        state.days = dayMap.values.sorted { $0.day < $1.day }

        var appMap: [String: AppUsage] = [:]
        for a in state.apps { appMap[a.day + "|" + a.name] = a }
        for n in r.apps {
            let key = n.day + "|" + n.name
            if let old = appMap[key], old.wifi + old.cell > n.wifi + n.cell { continue }
            appMap[key] = n
        }
        state.apps = Array(appMap.values)
    }

    func save() {
        if let d = try? JSONEncoder().encode(state) {
            try? d.write(to: url, options: .atomic)
        }
    }
}

final class Loc: NSObject, CLLocationManagerDelegate {
    static let shared = Loc()
    private let m = CLLocationManager()

    func start() {
        m.delegate = self
        if m.authorizationStatus == .notDetermined {
            m.requestWhenInUseAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DispatchQueue.main.async { Store.shared.refresh() }
    }
}

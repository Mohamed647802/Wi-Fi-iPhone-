import Foundation
import SQLite3

struct DayUsage: Codable, Hashable {
    var day: String
    var wifiDown: UInt64
    var wifiUp: UInt64
    var cellDown: UInt64
    var cellUp: UInt64
}

struct AppUsage: Codable, Hashable {
    var day: String
    var name: String
    var wifi: UInt64
    var cell: UInt64
}

struct DBResult {
    var days: [DayUsage] = []
    var apps: [AppUsage] = []
    var report: String = ""
}

// قراءة سجل الاستهلاك الحقيقي الذي يحتفظ به النظام (نفس مصدر الإعدادات ← الخلوي).
// يعمل فقط إذا ثُبّت التطبيق بصلاحيات النظام (TrollStore أو جيلبريك).
enum UsageDB {
    static let dir = "/private/var/wireless/Library/Databases/"
    static let file = "DataUsage.sqlite"

    private static func columns(_ db: OpaquePointer?, _ table: String) -> [String] {
        var st: OpaquePointer?
        var out: [String] = []
        if sqlite3_prepare_v2(db, "PRAGMA table_info(\(table));", -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW {
                if let c = sqlite3_column_text(st, 1) { out.append(String(cString: c)) }
            }
        }
        sqlite3_finalize(st)
        return out
    }

    private static func tables(_ db: OpaquePointer?) -> [String] {
        var st: OpaquePointer?
        var out: [String] = []
        if sqlite3_prepare_v2(db, "SELECT name FROM sqlite_master WHERE type='table';", -1, &st, nil) == SQLITE_OK {
            while sqlite3_step(st) == SQLITE_ROW {
                if let c = sqlite3_column_text(st, 0) { out.append(String(cString: c)) }
            }
        }
        sqlite3_finalize(st)
        return out
    }

    private static func pick(_ cols: [String], _ names: [String]) -> String? {
        for n in names where cols.contains(n) { return n }
        return nil
    }

    private static func u(_ v: Int64) -> UInt64 { v > 0 ? UInt64(v) : 0 }

    private static func text(_ st: OpaquePointer?, _ i: Int32) -> String {
        if let c = sqlite3_column_text(st, i) { return String(cString: c) }
        return ""
    }

    static func load() -> (DBResult?, String) {
        let fm = FileManager.default
        let src = dir + file
        let tmp = fm.temporaryDirectory.appendingPathComponent("du_copy", isDirectory: true)
        try? fm.removeItem(at: tmp)
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        let dst = tmp.appendingPathComponent(file).path

        do {
            try fm.copyItem(atPath: src, toPath: dst)
        } catch {
            return (nil, "تعذّر قراءة سجل النظام: \(error.localizedDescription). هذا متوقع عند التثبيت العادي. للحصول على الأيام السابقة ثبّت نسخة TrollStore أو استخدم جهازاً عليه جيلبريك.")
        }
        for ext in ["-wal", "-shm"] {
            try? fm.copyItem(atPath: src + ext, toPath: dst + ext)
        }

        var db: OpaquePointer?
        guard sqlite3_open_v2(dst, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            return (nil, "تعذّر فتح نسخة قاعدة بيانات النظام.")
        }
        defer { sqlite3_close(db) }

        let l = columns(db, "ZLIVEUSAGE")
        if l.isEmpty {
            return (nil, "جدول ZLIVEUSAGE غير موجود. الجداول الموجودة: \(tables(db).joined(separator: ", "))")
        }
        guard let tsCol = pick(l, ["ZTIMESTAMP"]),
              let wiCol = pick(l, ["ZWIFIIN"]),
              let woCol = pick(l, ["ZWIFIOUT"]),
              let ciCol = pick(l, ["ZWWANIN"]),
              let coCol = pick(l, ["ZWWANOUT"]) else {
            return (nil, "أعمدة غير متوقعة في ZLIVEUSAGE: \(l.joined(separator: ", "))")
        }
        let firstCol = pick(l, ["ZFIRSTTIMESTAMP"])
        let fk = l.first(where: { $0.contains("PROCESS") })

        let p = columns(db, "ZPROCESS")
        let bundleCol = pick(p, ["ZBUNDLENAME"])
        let procCol = pick(p, ["ZPROCNAME"])

        let firstExpr = firstCol != nil ? "l.\(firstCol!)" : "NULL"
        var bundleExpr = "NULL"
        var procExpr = "NULL"
        var join = ""
        if let fk = fk, !p.isEmpty {
            join = " LEFT JOIN ZPROCESS p ON l.\(fk) = p.Z_PK"
            if let b = bundleCol { bundleExpr = "p.\(b)" }
            if let n = procCol { procExpr = "p.\(n)" }
        }

        let sql = "SELECT l.\(tsCol), l.\(wiCol), l.\(woCol), l.\(ciCol), l.\(coCol), \(firstExpr), \(bundleExpr), \(procExpr) FROM ZLIVEUSAGE l\(join)"

        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &st, nil) == SQLITE_OK else {
            return (nil, "فشل الاستعلام: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(st) }

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")

        var days: [String: DayUsage] = [:]
        var apps: [String: AppUsage] = [:]
        var rows = 0
        var longRows = 0
        var minTs = Double.greatestFiniteMagnitude
        var maxTs = 0.0

        while sqlite3_step(st) == SQLITE_ROW {
            let ts = sqlite3_column_double(st, 0)
            if ts <= 0 { continue }
            let wi = u(sqlite3_column_int64(st, 1))
            let wo = u(sqlite3_column_int64(st, 2))
            let ci = u(sqlite3_column_int64(st, 3))
            let co = u(sqlite3_column_int64(st, 4))
            let first = sqlite3_column_double(st, 5)
            let b = text(st, 6)
            let pn = text(st, 7)
            let name = !b.isEmpty ? b : (!pn.isEmpty ? pn : "غير معروف")

            rows += 1
            if ts < minTs { minTs = ts }
            if ts > maxTs { maxTs = ts }
            if first > 0 && ts - first > 86400 { longRows += 1 }

            let day = f.string(from: Date(timeIntervalSinceReferenceDate: ts))

            var d = days[day] ?? DayUsage(day: day, wifiDown: 0, wifiUp: 0, cellDown: 0, cellUp: 0)
            d.wifiDown += wi
            d.wifiUp += wo
            d.cellDown += ci
            d.cellUp += co
            days[day] = d

            let key = day + "|" + name
            var a = apps[key] ?? AppUsage(day: day, name: name, wifi: 0, cell: 0)
            a.wifi += wi + wo
            a.cell += ci + co
            apps[key] = a
        }

        if rows == 0 { return (nil, "قاعدة بيانات النظام فارغة.") }

        let fromDay = f.string(from: Date(timeIntervalSinceReferenceDate: minTs))
        let toDay = f.string(from: Date(timeIntervalSinceReferenceDate: maxTs))
        var report = "سجلات النظام: \(rows) • من \(fromDay) إلى \(toDay)"
        if longRows > 0 {
            report += " • \(longRows) سجل يغطي أكثر من يوم ونُسب ليوم آخره"
        }
        let result = DBResult(days: Array(days.values), apps: Array(apps.values), report: report)
        return (result, report)
    }
}

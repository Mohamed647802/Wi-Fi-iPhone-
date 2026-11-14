import SwiftUI
import Charts

struct DayRow: Identifiable {
    let day: String
    let down: UInt64
    let up: UInt64
    var id: String { day }
}

struct NetRow: Identifiable {
    let name: String
    let total: UInt64
    var id: String { name }
}

struct AppRow: Identifiable {
    let name: String
    let total: UInt64
    var id: String { name }
}

struct UsageView: View {
    let kind: String
    @EnvironmentObject var store: Store
    @State private var from: Date = Calendar.current.date(byAdding: .day, value: -6, to: Date()) ?? Date()
    @State private var to: Date = Date()
    @State private var ssid: String? = nil
    @State private var showManual = false
    @State private var manualDay = Date()
    @State private var manualGB = ""

    var accent: Color { kind == "wifi" ? Theme.wifi : Theme.cell }
    var title: String { kind == "wifi" ? "استهلاك الواي فاي" : "استهلاك بيانات الشريحة" }

    // هل لدينا سجل النظام (الأيام السابقة الدقيقة)؟
    var useDB: Bool { !store.state.days.isEmpty }

    func inRangeDay(_ d: String) -> Bool {
        let f = Store.dayString(from)
        let t = Store.dayString(to)
        return d >= f && d <= t
    }

    var trackedInRange: [UsageEntry] {
        store.entries.filter { $0.kind == kind && inRangeDay($0.day) }
    }

    var trackedRows: [UsageEntry] {
        guard let s = ssid else { return trackedInRange }
        return trackedInRange.filter { $0.ssid == s }
    }

    var daily: [DayRow] {
        if useDB {
            var out: [DayRow] = []
            for d in store.state.days where inRangeDay(d.day) {
                let dn = kind == "wifi" ? d.wifiDown : d.cellDown
                let u = kind == "wifi" ? d.wifiUp : d.cellUp
                out.append(DayRow(day: d.day, down: dn, up: u))
            }
            return out.sorted { $0.day < $1.day }
        }
        let groups = Dictionary(grouping: trackedRows, by: { $0.day })
        var out: [DayRow] = []
        for (day, list) in groups {
            let d = list.reduce(UInt64(0)) { $0 + $1.down }
            let u = list.reduce(UInt64(0)) { $0 + $1.up }
            out.append(DayRow(day: day, down: d, up: u))
        }
        return out.sorted { $0.day < $1.day }
    }

    var down: UInt64 { daily.reduce(UInt64(0)) { $0 + $1.down } }
    var up: UInt64 { daily.reduce(UInt64(0)) { $0 + $1.up } }

    var networks: [NetRow] {
        let groups = Dictionary(grouping: trackedInRange, by: { $0.ssid })
        var out: [NetRow] = []
        for (name, list) in groups {
            let t = list.reduce(UInt64(0)) { $0 + $1.down + $1.up }
            out.append(NetRow(name: name, total: t))
        }
        return out.sorted { $0.total > $1.total }
    }

    var topApps: [AppRow] {
        var sums: [String: UInt64] = [:]
        for a in store.state.apps where inRangeDay(a.day) {
            let v = kind == "wifi" ? a.wifi : a.cell
            sums[a.name, default: 0] += v
        }
        var out: [AppRow] = []
        for (name, total) in sums where total > 0 {
            out.append(AppRow(name: name, total: total))
        }
        return Array(out.sorted { $0.total > $1.total }.prefix(12))
    }

    func setRange(_ days: Int) {
        to = Date()
        from = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
    }

    func setAll() {
        to = Date()
        var all: [String] = store.entries.filter { $0.kind == kind }.map { $0.day }
        all.append(contentsOf: store.state.days.map { $0.day })
        if let f = all.min() {
            let p = DateFormatter()
            p.dateFormat = "yyyy-MM-dd"
            p.locale = Locale(identifier: "en_US_POSIX")
            if let d = p.date(from: f) { from = d }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                header
                totalCard
                HStack(spacing: 12) {
                    tile("arrow.down.circle.fill", "تنزيل", fmt(down))
                    tile("arrow.up.circle.fill", "رفع", fmt(up))
                }
                rangeCard
                if kind == "cell" && !useDB { manualButton }
                if !daily.isEmpty { chartCard }
                dailyList
                if !topApps.isEmpty { appsList }
                if kind == "wifi" && !networks.isEmpty { networksGrid }
                sourceCard
            }
            .padding()
        }
        .refreshable { store.refresh() }
        .sheet(isPresented: $showManual) { manualSheet }
    }

    // MARK: - الأجزاء

    var header: some View {
        VStack(spacing: 4) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button { store.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .padding(10)
                        .background(accent.opacity(0.2), in: Circle())
                }
                .buttonStyle(.plain)
            }
            if let u = store.lastUpdate {
                Text("آخر تحديث: \(u.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    var totalCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 4) {
                Text(ssid == nil || useDB ? "المجموع للفترة المحددة" : "المجموع • \(ssid ?? "")")
                    .font(.footnote).foregroundStyle(.secondary)
                Text(fmt(down + up))
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .foregroundStyle(accent)
            }
        }
    }

    var rangeCard: some View {
        Card {
            VStack(spacing: 10) {
                DatePicker("من", selection: $from, in: ...to, displayedComponents: .date)
                DatePicker("إلى", selection: $to, in: from...Date(), displayedComponents: .date)
                HStack(spacing: 8) {
                    chip("اليوم") { setRange(1) }
                    chip("7 أيام") { setRange(7) }
                    chip("30 يوم") { setRange(30) }
                    chip("الكل") { setAll() }
                }
            }
        }
    }

    var manualButton: some View {
        Button { showManual = true } label: {
            Label("إضافة استهلاك سابق من إعدادات الخلوي", systemImage: "plus.circle.fill")
                .font(.footnote.bold())
                .frame(maxWidth: .infinity)
                .padding(12)
                .background(accent.opacity(0.2), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    var chartCard: some View {
        Card {
            Chart(daily) { d in
                BarMark(
                    x: .value("اليوم", String(d.day.suffix(5))),
                    y: .value("GB", Double(d.down + d.up) / 1e9)
                )
                .foregroundStyle(accent)
                .cornerRadius(5)
            }
            .frame(height: 170)
        }
    }

    var dailyList: some View {
        VStack(spacing: 12) {
            Text("التفصيل اليومي").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            if daily.isEmpty {
                Card {
                    Text("لا توجد بيانات في هذه الفترة.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            ForEach(daily) { d in
                Card {
                    HStack {
                        Text(d.day).font(.subheadline.monospacedDigit())
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(fmt(d.down + d.up)).bold().foregroundStyle(accent)
                            Text("↓ \(fmt(d.down))  ↑ \(fmt(d.up))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    var appsList: some View {
        VStack(spacing: 12) {
            Text("أكثر التطبيقات استخداماً").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(topApps) { a in
                Card {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(a.name).font(.subheadline.bold()).lineLimit(1)
                            Spacer()
                            Text(fmt(a.total)).font(.subheadline).foregroundStyle(accent)
                        }
                        ProgressView(value: Double(a.total), total: Double(topApps.first?.total ?? 1))
                            .tint(accent)
                    }
                }
            }
        }
    }

    var networksGrid: some View {
        VStack(spacing: 12) {
            Text(useDB ? "الشبكات (منذ تثبيت التطبيق)" : "الشبكات")
                .font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(networks) { n in
                    networkTile(n)
                }
            }
        }
    }

    func networkTile(_ n: NetRow) -> some View {
        let selected = (ssid == n.name) && !useDB
        return Button {
            if !useDB { ssid = (ssid == n.name) ? nil : n.name }
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: "wifi").foregroundStyle(accent)
                Spacer()
                Text(n.name).font(.subheadline.bold()).lineLimit(1)
                Text(fmt(n.total)).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .aspectRatio(1, contentMode: .fit)
            .background(selected ? accent.opacity(0.25) : Color.white.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(selected ? accent : Color.white.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
    }

    var sourceCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text(useDB ? "المصدر: سجل استهلاك النظام (دقيق، يشمل الأيام السابقة)"
                           : "المصدر: عدّادات التطبيق (من لحظة التثبيت فقط)")
                    .font(.footnote.bold())
                    .foregroundStyle(useDB ? accent : Color.orange)
                if !store.dbStatus.isEmpty {
                    Text(store.dbStatus)
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    var manualSheet: some View {
        NavigationStack {
            Form {
                DatePicker("التاريخ", selection: $manualDay, in: ...Date(), displayedComponents: .date)
                TextField("الاستهلاك بالجيجا (مثال: 12.5)", text: $manualGB)
                    .keyboardType(.decimalPad)
            }
            .navigationTitle("استهلاك سابق")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") {
                        let v = Double(manualGB.replacingOccurrences(of: ",", with: ".")) ?? 0
                        if v > 0 { store.addManual(day: manualDay, bytes: UInt64(v * 1e9)) }
                        manualGB = ""
                        showManual = false
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { showManual = false }
                }
            }
        }
        .preferredColorScheme(.dark)
        .environment(\.layoutDirection, .rightToLeft)
        .presentationDetents([.medium])
    }

    func tile(_ icon: String, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundStyle(accent)
            Spacer()
            Text(label).font(.footnote).foregroundStyle(.secondary)
            Text(value).font(.title3.bold())
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .aspectRatio(1, contentMode: .fit)
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(Color.white.opacity(0.1)))
    }

    func chip(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.footnote.bold())
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(accent.opacity(0.2), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

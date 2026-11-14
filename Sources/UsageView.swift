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

    var inRange: [UsageEntry] {
        let f = Store.dayString(from)
        let t = Store.dayString(to)
        return store.entries.filter { $0.kind == kind && $0.day >= f && $0.day <= t }
    }

    var rows: [UsageEntry] {
        guard let s = ssid else { return inRange }
        return inRange.filter { $0.ssid == s }
    }

    var down: UInt64 { rows.reduce(UInt64(0)) { $0 + $1.down } }
    var up: UInt64 { rows.reduce(UInt64(0)) { $0 + $1.up } }

    var daily: [DayRow] {
        let groups = Dictionary(grouping: rows, by: { $0.day })
        var out: [DayRow] = []
        for (day, list) in groups {
            let d = list.reduce(UInt64(0)) { $0 + $1.down }
            let u = list.reduce(UInt64(0)) { $0 + $1.up }
            out.append(DayRow(day: day, down: d, up: u))
        }
        return out.sorted { $0.day < $1.day }
    }

    var networks: [NetRow] {
        let groups = Dictionary(grouping: inRange, by: { $0.ssid })
        var out: [NetRow] = []
        for (name, list) in groups {
            let t = list.reduce(UInt64(0)) { $0 + $1.down + $1.up }
            out.append(NetRow(name: name, total: t))
        }
        return out.sorted { $0.total > $1.total }
    }

    func setRange(_ days: Int) {
        to = Date()
        from = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date()) ?? Date()
    }

    func setAll() {
        to = Date()
        let first = store.entries.filter { $0.kind == kind }.map { $0.day }.min()
        if let f = first {
            let p = DateFormatter()
            p.dateFormat = "yyyy-MM-dd"
            p.locale = Locale(identifier: "en_US_POSIX")
            if let d = p.date(from: f) { from = d }
        }
    }

    var cardBg: some ShapeStyle { Color.white.opacity(0.07) }

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
                if kind == "cell" { manualButton }
                if kind == "wifi" && !networks.isEmpty { networksGrid }
                if !daily.isEmpty { chartCard }
                dailyList
                Text("ملاحظة: أقدم بيانات يوفرها النظام هي منذ آخر إقلاع للجهاز، وتُنسب لتاريخ الإقلاع. الاستهلاك بين كل فتحتين يُنسب للشبكة المتصل بها وقت الفتح.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                Text(ssid == nil ? "المجموع للفترة المحددة" : "المجموع • \(ssid ?? "")")
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

    var networksGrid: some View {
        VStack(spacing: 12) {
            Text("الشبكات").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(networks) { n in
                    networkTile(n)
                }
            }
        }
    }

    func networkTile(_ n: NetRow) -> some View {
        let selected = (ssid == n.name)
        return Button {
            ssid = selected ? nil : n.name
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

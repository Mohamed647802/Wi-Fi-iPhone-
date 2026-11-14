import SwiftUI
import Charts

struct UsageView: View {
    let kind: String
    @EnvironmentObject var store: Store
    @State private var from = Calendar.current.date(byAdding: .day, value: -6, to: Date())!
    @State private var to = Date()
    @State private var ssid: String? = nil
    private let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()

    var accent: Color { kind == "wifi" ? Theme.wifi : Theme.cell }
    var title: String { kind == "wifi" ? "استهلاك الواي فاي" : "استهلاك بيانات الشريحة" }

    var inRange: [Entry] {
        let f = Store.dayString(from), t = Store.dayString(to)
        return store.entries.filter { $0.kind == kind && $0.day >= f && $0.day <= t }
    }
    var rows: [Entry] { ssid == nil ? inRange : inRange.filter { $0.ssid == ssid } }
    var down: UInt64 { rows.reduce(0) { $0 + $1.down } }
    var up: UInt64 { rows.reduce(0) { $0 + $1.up } }

    var daily: [(day: String, down: UInt64, up: UInt64)] {
        Dictionary(grouping: rows, by: \.day)
            .map { (day: $0.key, down: $0.value.reduce(0) { $0 + $1.down }, up: $0.value.reduce(0) { $0 + $1.up }) }
            .sorted { $0.day < $1.day }
    }
    var networks: [(name: String, total: UInt64)] {
        Dictionary(grouping: inRange, by: \.ssid)
            .map { (name: $0.key, total: $0.value.reduce(0) { $0 + $1.down + $1.up }) }
            .sorted { $0.total > $1.total }
    }

    func setRange(_ days: Int) {
        to = Date()
        from = Calendar.current.date(byAdding: .day, value: -(days - 1), to: Date())!
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(title).font(.title2.bold()).frame(maxWidth: .infinity, alignment: .leading)

                // مستطيل كبير: المجموع
                Card {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(ssid.map { "المجموع • \($0)" } ?? "المجموع للفترة المحددة")
                            .font(.footnote).foregroundStyle(.secondary)
                        Text(fmt(down + up)).font(.system(size: 40, weight: .bold, design: .rounded))
                            .foregroundStyle(accent)
                    }
                }

                // مربعان: تنزيل / رفع
                HStack(spacing: 12) {
                    tile("arrow.down.circle.fill", "تنزيل", fmt(down))
                    tile("arrow.up.circle.fill", "رفع", fmt(up))
                }

                // اختيار الفترة
                Card {
                    VStack(spacing: 10) {
                        HStack {
                            DatePicker("من", selection: $from, in: ...to, displayedComponents: .date)
                        }
                        DatePicker("إلى", selection: $to, in: from...Date(), displayedComponents: .date)
                        HStack(spacing: 8) {
                            chip("اليوم") { setRange(1) }
                            chip("7 أيام") { setRange(7) }
                            chip("30 يوم") { setRange(30) }
                        }
                    }
                }

                // الشبكات (واي فاي فقط)
                if kind == "wifi" && !networks.isEmpty {
                    Text("الشبكات").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(networks, id: \.name) { n in
                            Button { ssid = (ssid == n.name) ? nil : n.name } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Image(systemName: "wifi").foregroundStyle(accent)
                                    Spacer()
                                    Text(n.name).font(.subheadline.bold()).lineLimit(1)
                                    Text(fmt(n.total)).font(.caption).foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .aspectRatio(1, contentMode: .fit)
                                .background(ssid == n.name ? accent.opacity(0.25) : .white.opacity(0.07),
                                            in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(ssid == n.name ? accent : .white.opacity(0.1)))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // رسم بياني
                if !daily.isEmpty {
                    Card {
                        Chart(daily, id: \.day) { d in
                            BarMark(x: .value("اليوم", String(d.day.suffix(5))),
                                    y: .value("GB", Double(d.down + d.up) / 1e9))
                                .foregroundStyle(accent.gradient)
                                .cornerRadius(5)
                        }
                        .frame(height: 170)
                    }
                }

                // التفصيل اليومي مرتباً زمنياً
                Text("التفصيل اليومي").font(.headline).frame(maxWidth: .infinity, alignment: .leading)
                if daily.isEmpty {
                    Card { Text("لا توجد بيانات مسجلة في هذه الفترة بعد. التسجيل يبدأ من أول تشغيل للتطبيق.")
                        .font(.footnote).foregroundStyle(.secondary) }
                }
                ForEach(daily, id: \.day) { d in
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
            .padding()
        }
        .onReceive(timer) { _ in store.tick() }
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
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.1)))
    }

    func chip(_ t: String, _ a: @escaping () -> Void) -> some View {
        Button(action: a) {
            Text(t).font(.footnote.bold()).padding(.horizontal, 14).padding(.vertical, 8)
                .background(accent.opacity(0.2), in: Capsule())
        }.buttonStyle(.plain)
    }
}

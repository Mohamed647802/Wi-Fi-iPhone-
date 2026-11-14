import SwiftUI

enum Theme {
    static let bg = LinearGradient(
        colors: [Color(red: 0.03, green: 0.04, blue: 0.12),
                 Color(red: 0.09, green: 0.04, blue: 0.22),
                 Color(red: 0.02, green: 0.11, blue: 0.17)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
    static let wifi = Color(red: 0.25, green: 0.8, blue: 1.0)
    static let cell = Color(red: 0.4, green: 1.0, blue: 0.6)
}

struct Card<Content: View>: View {
    var content: () -> Content
    init(@ViewBuilder _ c: @escaping () -> Content) { content = c }
    var body: some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(.white.opacity(0.1)))
    }
}

func fmt(_ b: UInt64) -> String {
    let v = Double(b)
    if v >= 1e9 { return String(format: "%.2f GB", v / 1e9) }
    if v >= 1e6 { return String(format: "%.1f MB", v / 1e6) }
    return String(format: "%.0f KB", v / 1e3)
}

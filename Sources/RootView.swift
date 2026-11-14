import SwiftUI

struct RootView: View {
    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            TabView {
                UsageView(kind: "wifi")
                    .tabItem { Label("الواي فاي", systemImage: "wifi") }
                UsageView(kind: "cell")
                    .tabItem { Label("بيانات الشريحة", systemImage: "antenna.radiowaves.left.and.right") }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
    }
}

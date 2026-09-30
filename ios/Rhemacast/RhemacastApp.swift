import SwiftUI

/// Deep-link router: rhemacast://listen?ip=<host> tunes + auto-plays.
final class DeepLinkRouter: ObservableObject {
    @Published var ip: String? = nil
    @Published var nonce = 0

    func open(_ url: URL) {
        guard url.scheme == "rhemacast",
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let ip = parts.queryItems?.first(where: { $0.name == "ip" })?.value,
              !ip.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        self.ip = ip
        self.nonce += 1
    }
}

@main
struct RhemacastApp: App {
    @StateObject private var links = DeepLinkRouter()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(links)
        }
        .onOpenURL { links.open($0) }
    }
}

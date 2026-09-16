import AVFoundation
import Combine
import Foundation

/// Listener output routing. Policy: never auto-select the loudspeaker —
/// Auto resolves to Headphones (phone/wired/Bluetooth via system
/// priority). Loudspeaker stays available as an explicit user choice.
enum ListenerOutput: String, CaseIterable, Identifiable {
    case auto
    case headphones
    case speaker

    var id: String { rawValue }

    var label: String {
        switch self {
        case .auto: return "Auto"
        case .headphones: return "Headphones"
        case .speaker: return "Loudspeaker"
        }
    }
}

final class AudioRouter: ObservableObject {
    static let shared = AudioRouter()

    @Published var selection: ListenerOutput = .auto
    @Published var available: [ListenerOutput] = [.auto, .headphones, .speaker]

    private var observer: NSObjectProtocol?

    init() {
        observer = NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Re-assert override: route changes can reset it to speaker.
            self?.apply()
        }
    }

    deinit {
        if let o = observer { NotificationCenter.default.removeObserver(o) }
    }

    func refreshAvailable() {
        // Fixed list: Bluetooth/wired headsets are handled implicitly by
        // system priority, not as separate choices.
        available = [.auto, .headphones, .speaker]
    }

    /// Resolve AUTO to a real device; never resolves to loudspeaker.
    func effective() -> ListenerOutput {
        if selection != .auto { return selection }
        return .headphones
    }

    /// Apply routing. Call on connect + on selection change.
    func apply() {
        let e = effective()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback, mode: .voiceChat,
                options: [.allowBluetooth, .allowBluetoothA2DP]
            )
            // .none = Headphones with automatic BT/wired priority;
            // .speaker only when the user explicitly chose loudspeaker.
            try session.overrideOutputAudioPort(e == .speaker ? .speaker : .none)
            try session.setActive(true)
        } catch {
            // Leave system routing untouched rather than failing playback.
        }
    }
}

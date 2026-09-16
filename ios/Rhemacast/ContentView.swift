import SwiftUI
import MediaPlayer
import SafariServices

struct ContentView: View {
    @AppStorage("serverIP") private var serverIP = "192.168.4.1"
    @StateObject private var client = WebRTCClient()
    @State private var muted = false

    var body: some View {
        NavigationView {
            Form {
                Section("Server") {
                    TextField("Server IP", text: $serverIP)
                        .keyboardType(.decimalPad)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    Button(client.isLive ? "Disconnect" : "Connect") {
                        if client.isLive {
                            client.disconnect()
                        } else {
                            client.connect(hostIP: serverIP)
                        }
                    }
                }
                Section("Status") {
                    Text(client.status)
                        .foregroundColor(client.isLive ? .green : .secondary)
                    Text(client.statsLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("Audio") {
                    Toggle("Mute", isOn: $muted)
                        .onChange(of: muted) { client.setMuted($0) }
                    VStack(alignment: .leading) {
                        Text("Volume (system)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        SystemVolumeView()
                            .frame(height: 32)
                    }
                }
                Section("Translator") {
                    let ip = serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
                    Link("Translator controls (admin)", destination: URL(string: "http://\(ip.isEmpty ? "192.168.4.1" : ip):8080/admin.html")!)
                    Link("Web test player", destination: URL(string: "http://\(ip.isEmpty ? "192.168.4.1" : ip):8080/listen.html")!)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Rhemacast")
        }
    }
}

/// Native system-volume slider (WebRTC has no per-track gain on iOS).
struct SystemVolumeView: UIViewRepresentable {
    func makeUIView(context: Context) -> MPVolumeView {
        MPVolumeView()
    }
    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}

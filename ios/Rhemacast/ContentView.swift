import SwiftUI
import MediaPlayer
import SafariServices

struct ContentView: View {
    @AppStorage("serverIP") private var serverIP = "192.168.4.1"
    @StateObject private var client = WebRTCClient()
    @ObservedObject private var router = AudioRouter.shared
    @State private var muted = false
    @State private var settingsOpen = false

    private var host: String {
        let t = serverIP.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "192.168.4.1" : t
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                VStack(spacing: 4) {
                    Text(client.status)
                        .font(.headline)
                        .foregroundColor(client.isLive ? .green : .secondary)
                    Text(client.statsLine)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.top, 8)

                Spacer()

                // Big central on/off toggle.
                Button {
                    if client.isLive {
                        client.disconnect()
                    } else {
                        client.connect(hostIP: serverIP)
                    }
                } label: {
                    Text(client.isLive ? "Stop" : "Listen")
                        .font(.title)
                        .bold()
                        .frame(width: 200, height: 200)
                        .background(client.isLive ? Color.red : Color.green)
                        .foregroundColor(.white)
                        .clipShape(Circle())
                }
                .accessibilityLabel(client.isLive ? "Stop listening" : "Start listening")

                Spacer()

                VStack(alignment: .leading, spacing: 8) {
                    // Compact output picker (stays on screen, small).
                    HStack(spacing: 4) {
                        Text("Output")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Picker("Output", selection: $router.selection) {
                            ForEach(router.available) { o in
                                Text(o.label).tag(o)
                            }
                        }
                        .pickerStyle(.menu)
                        .font(.caption)
                        .labelsHidden()
                    }
                    .onChange(of: router.selection) { _ in router.apply() }
                    Toggle("Mute", isOn: $muted)
                        .onChange(of: muted) { client.setMuted($0) }
                    Text("Volume (system)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    SystemVolumeView()
                        .frame(height: 32)
                }

                // Non-essential settings live in a popup so the big button never moves.
                Button("Settings") { settingsOpen = true }
                    .font(.caption)
                .sheet(isPresented: $settingsOpen) {
                    NavigationView {
                        Form {
                            Section("Server") {
                                TextField("Server IP", text: $serverIP)
                                    .keyboardType(.decimalPad)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                Text("WHEP: http://\(host):8080/whep")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Section("Links") {
                                Link("Broadcast controls (admin)", destination: URL(string: "http://\(host):8080/admin.html")!)
                                Link("Web test player", destination: URL(string: "http://\(host):8080/listen.html")!)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .navigationTitle("Settings")
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { settingsOpen = false }
                            }
                        }
                        .presentationDetents([.medium])
                        .presentationDragIndicator(.visible)
                    }
                }
            }
            .padding()
            .navigationTitle("Rhemacast")
            .onAppear { router.refreshAvailable() }
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

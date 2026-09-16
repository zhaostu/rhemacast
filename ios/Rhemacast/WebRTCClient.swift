import WebRTC
import AVFoundation
import Foundation

/// Audio-only recvonly WebRTC listener via WHEP (MediaMTX).
final class WebRTCClient: NSObject, ObservableObject {
    @Published var status: String = "disconnected"
    @Published var statsLine: String = "—"
    @Published var isLive = false

    private var factory: RTCPeerConnectionFactory?
    private var peerConnection: RTCPeerConnection?
    private var audioTrack: RTCAudioTrack?
    private var resourceURL: URL?
    private var statsTimer: Timer?
    private var muted = false

    var whepURL: URL?

    // MARK: - Connect

    func connect(hostIP: String) {
        teardown()
        let ip = hostIP.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !ip.isEmpty else { status = "error: empty IP"; return }
        guard let url = URL(string: "http://\(ip):8080/whep") else {
            status = "error: bad IP"
            return
        }
        whepURL = url
        status = "connecting…"
        configureAudioSession()
        setupPeerConnection()
        makeOfferAndWhep(url: url)
    }

    func disconnect() {
        teardown()
        DispatchQueue.main.async {
            self.isLive = false
            self.status = "disconnected"
            self.statsLine = "—"
        }
    }

    private func teardown() {
        statsTimer?.invalidate()
        statsTimer = nil
        if let res = resourceURL {
            var req = URLRequest(url: res)
            req.httpMethod = "DELETE"
            URLSession.shared.dataTask(with: req).resume()
            resourceURL = nil
        }
        audioTrack = nil
        if let pc = peerConnection {
            pc.close()
        }
        peerConnection = nil
    }

    func setMuted(_ mute: Bool) {
        muted = mute
        audioTrack?.isEnabled = !mute
    }

    // MARK: - Setup

    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance
        do {
            try session.setCategory(.playback, mode: .voiceChat, options: [])
            try session.setActive(true)
        } catch {
            DispatchQueue.main.async { self.status = "audio session error: \(error.localizedDescription)" }
        }
    }

    private func setupPeerConnection() {
        if factory == nil {
            factory = RTCPeerConnectionFactory()
        }
        guard let factory else { status = "error: no WebRTC factory"; return }
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"],
            optionalConstraints: nil
        )
        peerConnection = factory.peerConnection(with: config, constraints: constraints, delegate: self)
        if peerConnection == nil {
            status = "error: peer connection failed"
        }
    }

    private func makeOfferAndWhep(url: URL) {
        guard let pc = peerConnection else { return }
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: ["OfferToReceiveAudio": "true", "OfferToReceiveVideo": "false"],
            optionalConstraints: nil
        )
        pc.offer(for: constraints) { [weak self] offer, error in
            guard let self else { return }
            if let error {
                self.setStatus("offer error: \(error.localizedDescription)")
                return
            }
            guard let offer else { self.setStatus("offer error: nil SDP"); return }
            pc.setLocalDescription(offer) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.setStatus("local SDP error: \(error.localizedDescription)")
                    return
                }
                self.postWhepOffer(url: url, sdp: offer.sdp)
            }
        }
    }

    private func postWhepOffer(url: URL, sdp: String) {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/sdp", forHTTPHeaderField: "Content-Type")
        req.setValue("application/sdp", forHTTPHeaderField: "Accept")
        req.httpBody = sdp.data(using: .utf8)
        req.timeoutInterval = 10
        URLSession.shared.dataTask(with: req) { [weak self] data, response, error in
            guard let self else { return }
            if let error {
                self.setStatus("offline: \(error.localizedDescription)")
                return
            }
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode),
                  let data, let answerSDP = String(data: data, encoding: .utf8),
                  !answerSDP.isEmpty else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                self.setStatus("WHEP error: HTTP \(code)")
                return
            }
            if let location = http.value(forHTTPHeaderField: "Location") {
                self.resourceURL = URL(string: location, relativeTo: url)?.absoluteURL ?? URL(string: location)
            }
            let answer = RTCSessionDescription(type: .answer, sdp: answerSDP)
            self.peerConnection?.setRemoteDescription(answer) { [weak self] error in
                guard let self else { return }
                if let error {
                    self.setStatus("remote SDP error: \(error.localizedDescription)")
                    return
                }
                self.setStatus("live")
                DispatchQueue.main.async { self.isLive = true }
                self.startStatsPolling()
            }
        }.resume()
    }

    // MARK: - Stats

    private func startStatsPolling() {
        DispatchQueue.main.async {
            self.statsTimer?.invalidate()
            self.statsTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
                self?.pollStats()
            }
        }
    }

    private func pollStats() {
        peerConnection?.stats(for: nil, statsOutputLevel: .standard) { [weak self] reports in
            guard let self else { return }
            var jitterMs: Double?
            var rttMs: Double?
            for report in reports {
                let t = report.type
                let v = report.values as? [String: NSObject] ?? [:]
                if t == "inbound-rtp", let j = (v["jitter"] as? NSNumber)?.doubleValue {
                    jitterMs = j * 1000.0
                }
                if t == "remote-inbound-rtp", let r = (v["roundTripTime"] as? NSNumber)?.doubleValue {
                    rttMs = r * 1000.0
                }
                if t == "candidate-pair",
                   let nominated = v["nominated"] as? NSNumber, nominated.boolValue,
                   let r = (v["currentRoundTripTime"] as? NSNumber)?.doubleValue, rttMs == nil {
                    rttMs = r * 1000.0
                }
            }
            let line: String
            switch (rttMs, jitterMs) {
            case let (r?, j?): line = String(format: "RTT %.0f ms · jitter %.1f ms", r, j)
            case let (r?, nil): line = String(format: "RTT %.0f ms", r)
            case let (nil, j?): line = String(format: "jitter %.1f ms", j)
            default: line = "live · stats pending…"
            }
            DispatchQueue.main.async { self.statsLine = line }
        }
    }

    private func setStatus(_ s: String) {
        DispatchQueue.main.async {
            self.status = s
            self.isLive = (s == "live")
        }
    }
}

// MARK: - RTCPeerConnectionDelegate

extension WebRTCClient: RTCPeerConnectionDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        if let track = stream.audioTracks.first {
            audioTrack = track
            track.isEnabled = !muted
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        switch newState {
        case .connected, .completed: setStatus("live")
        case .disconnected: setStatus("reconnecting…")
        case .failed: setStatus("connection failed")
        case .closed: setStatus("disconnected")
        default: break
        }
    }
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd rtpReceiver: RTCRtpReceiver, streams mediaStreams: [RTCMediaStream]) {
        if let track = rtpReceiver.track as? RTCAudioTrack {
            audioTrack = track
            track.isEnabled = !muted
        }
    }
}

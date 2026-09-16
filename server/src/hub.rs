//! WebRTC fan-out (WHEP) + admin API + embedded web UI.
//!
//! One `RTCPeerConnection` per listener, all fed the same Opus packets:
//! capture encodes once, every session just relays. Protocol matches the
//! old MediaMTX setup (WHEP + Opus 48kHz), so the iOS/Android apps and
//! `listen.html` work unchanged — only the port moved to :8080.

use anyhow::{Context, Result};
use axum::{
    Router,
    extract::{Path, State},
    http::{HeaderMap, StatusCode, header},
    response::{Html, IntoResponse, Redirect},
    routing::{delete, get, post},
};
use std::{
    collections::{HashMap, VecDeque},
    net::SocketAddr,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicU32, AtomicU64, Ordering},
    },
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};
use tokio::sync::broadcast;
use webrtc::{
    api::{APIBuilder, media_engine::MediaEngine},
    peer_connection::{RTCPeerConnection, sdp::session_description::RTCSessionDescription},
    rtp::packet::Packet,
    rtp_transceiver::rtp_codec::RTCRtpCodecCapability,
    track::track_local::{TrackLocal, TrackLocalWriter, track_local_static_rtp::TrackLocalStaticRTP},
};

use crate::audio::{FRAME_SAMPLES, OPUS_PT, SAMPLE_RATE};

const LISTEN_HTML: &str = include_str!("../web/listen.html");
const ADMIN_HTML: &str = include_str!("../web/admin.html");

pub struct AppState {
    pub version: &'static str,
    pub started: Instant,
    pub running: AtomicBool,
    pub level_peak: AtomicU32, // f32 bits
    pub level_ts: AtomicU64,   // unix millis of last emitted frame
    pub sessions: Mutex<HashMap<String, Arc<RTCPeerConnection>>>,
    pub events: Mutex<VecDeque<String>>,
    pub webrtc_api: Arc<webrtc::api::API>,
    pub frames: broadcast::Sender<Packet>,
    pub udp_out: Option<SocketAddr>,
    pub token: String,
    next_id: AtomicU64,
}

impl AppState {
    pub fn new(udp_out: Option<SocketAddr>) -> Arc<Self> {
        let mut m = MediaEngine::default();
        m.register_default_codecs()
            .expect("register webrtc codecs");
        let api = APIBuilder::default().with_media_engine(m).build();
        let (frames, _) = broadcast::channel(64);
        let st = Arc::new(Self {
            version: env!("CARGO_PKG_VERSION"),
            started: Instant::now(),
            running: AtomicBool::new(true),
            level_peak: AtomicU32::new(0),
            level_ts: AtomicU64::new(0),
            sessions: Mutex::new(HashMap::new()),
            events: Mutex::new(VecDeque::with_capacity(512)),
            webrtc_api: Arc::new(api),
            frames,
            udp_out,
            token: std::env::var("ADMIN_TOKEN").unwrap_or_default(),
            next_id: AtomicU64::new(1),
        });
        if st.token.is_empty() {
            eprintln!("WARN: ADMIN_TOKEN empty — /api/* open to LAN");
        }
        st
    }

    pub fn log(&self, msg: &str) {
        eprintln!("rhemacastd: {msg}");
        let mut ev = self.events.lock().unwrap();
        if ev.len() >= 500 {
            ev.pop_front();
        }
        ev.push_back(format!("[{}] {msg}", now_unix()));
    }

    pub fn is_running(&self) -> bool {
        self.running.load(Ordering::Relaxed)
    }

    pub fn set_level(&self, peak: f32) {
        self.level_peak.store(peak.to_bits(), Ordering::Relaxed);
        self.level_ts.store(now_unix_millis(), Ordering::Relaxed);
    }
}

fn now_unix() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0)
}

fn now_unix_millis() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as u64)
        .unwrap_or(0)
}

pub async fn serve(state: Arc<AppState>, port: u16) -> Result<()> {
    let app = Router::new()
        .route("/whep", post(whep_post))
        .route("/whep/{id}", delete(whep_delete))
        .route("/api/status", get(api_status))
        .route("/api/level", get(api_level))
        .route("/api/logs", get(api_logs))
        .route("/api/publish/{action}", post(api_publish))
        .route("/", get(|| async { Redirect::to("/admin.html") }))
        .route("/listen.html", get(|| async { Html(LISTEN_HTML) }))
        .route("/admin.html", get(|| async { Html(ADMIN_HTML) }))
        .with_state(state);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    eprintln!("rhemacastd: listening on http://{addr} (WHEP /api/* web)");
    axum::serve(
        tokio::net::TcpListener::bind(addr)
            .await
            .context("bind http")?,
        app.into_make_service(),
    )
    .await
    .context("http serve")?;
    Ok(())
}

// --- WHEP: client POSTs an offer, gets an answer; DELETE tears down ---

async fn new_session_pc(
    st: &AppState,
) -> Result<(Arc<RTCPeerConnection>, Arc<TrackLocalStaticRTP>)> {
    let pc = Arc::new(
        st.webrtc_api
            .new_peer_connection(webrtc::peer_connection::configuration::RTCConfiguration {
                ..Default::default()
            })
            .await?,
    );
    let track = Arc::new(TrackLocalStaticRTP::new(
        RTCRtpCodecCapability {
            mime_type: webrtc::api::media_engine::MIME_TYPE_OPUS.to_owned(),
            clock_rate: SAMPLE_RATE,
            channels: 2, // RFC 7587: Opus is always advertised as stereo
            sdp_fmtp_line: "minptime=10;useinbandfec=1".to_owned(),
            ..Default::default()
        },
        "audio".to_owned(),
        "rhemacast".to_owned(),
    ));
    pc.add_track(track.clone() as Arc<dyn TrackLocal + Send + Sync>)
        .await?;
    Ok((pc, track))
}

async fn whep_post(
    State(st): State<Arc<AppState>>,
    body: String,
) -> impl IntoResponse {
    let fail = |code: StatusCode, msg: String| -> axum::response::Response {
        st.log(&format!("whep reject {code}: {msg}"));
        (code, msg).into_response()
    };
    let offer = match RTCSessionDescription::offer(body) {
        Ok(o) => o,
        Err(e) => return fail(StatusCode::BAD_REQUEST, format!("bad offer: {e}")),
    };
    let (pc, track) = match new_session_pc(&st).await {
        Ok(t) => t,
        Err(e) => return fail(StatusCode::INTERNAL_SERVER_ERROR, format!("pc: {e:#}")),
    };
    if let Err(e) = pc.set_remote_description(offer).await {
        return fail(
            StatusCode::BAD_REQUEST,
            format!("remote description: {e}"),
        );
    }
    let answer = match pc.create_answer(None).await {
        Ok(a) => a,
        Err(e) => return fail(StatusCode::INTERNAL_SERVER_ERROR, format!("answer: {e}")),
    };
    if let Err(e) = pc.set_local_description(answer).await {
        return fail(StatusCode::INTERNAL_SERVER_ERROR, format!("local sdp: {e}"));
    }
    // Non-trickle: wait (bounded) for ICE gathering so the answer is complete.
    let mut gather = pc.gathering_complete_promise().await;
    let _ = tokio::time::timeout(Duration::from_secs(3), gather.recv()).await;
    let sdp = match pc.local_description().await {
        Some(d) => d.sdp,
        None => return fail(StatusCode::INTERNAL_SERVER_ERROR, "no local sdp".into()),
    };

    let id = format!("{:x}", st.next_id.fetch_add(1, Ordering::Relaxed));
    st.sessions.lock().unwrap().insert(id.clone(), pc.clone());
    st.log(&format!(
        "listener {id} connected ({} total)",
        st.sessions.lock().unwrap().len()
    ));

    // Fan-out task: same Opus packets to this track until the peer goes away.
    let st2 = st.clone();
    let id2 = id.clone();
    tokio::spawn(async move {
        use tokio::sync::broadcast::error::RecvError;
        let mut rx = st2.frames.subscribe();
        loop {
            match tokio::time::timeout(Duration::from_secs(5), rx.recv()).await {
                Ok(Ok(pkt)) => {
                    if track.write_rtp(&pkt).await.is_err() {
                        break;
                    }
                }
                Ok(Err(RecvError::Lagged(_))) => continue, // realtime: skip, never catch up
                Ok(Err(RecvError::Closed)) => break,       // producer gone
                Err(_timeout) => {} // no frames (source paused?) — fall to state check
            }
            use webrtc::peer_connection::peer_connection_state::RTCPeerConnectionState as S;
            if matches!(pc.connection_state(), S::Closed | S::Failed) {
                break;
            }
        }
        st2.sessions.lock().unwrap().remove(&id2);
        let _ = pc.close().await;
        st2.log(&format!("listener {id2} gone"));
    });

    (
        StatusCode::CREATED,
        [
            (header::LOCATION, format!("/whep/{id}")),
            (header::CONTENT_TYPE, "application/sdp".to_owned()),
        ],
        sdp,
    )
        .into_response()
}

async fn whep_delete(State(st): State<Arc<AppState>>, Path(id): Path<String>) -> impl IntoResponse {
    let pc = st.sessions.lock().unwrap().remove(&id);
    match pc {
        Some(pc) => {
            let _ = pc.close().await;
            st.log(&format!("listener {id} deleted"));
            (StatusCode::OK, "bye").into_response()
        }
        None => (StatusCode::NOT_FOUND, "unknown session").into_response(),
    }
}

// --- Admin API (Bearer token on /api/* when ADMIN_TOKEN is set) ---

fn unauthorized(st: &AppState, headers: &HeaderMap) -> Option<axum::response::Response> {
    if st.token.is_empty() {
        return None;
    }
    let ok = headers
        .get(header::AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .map(|v| v == format!("Bearer {}", st.token))
        .unwrap_or(false);
    (!ok).then(|| {
        (
            StatusCode::UNAUTHORIZED,
            [(header::CONTENT_TYPE, "application/json")],
            r#"{"error":"unauthorized"}"#,
        )
            .into_response()
    })
}

fn json(code: StatusCode, v: serde_json::Value) -> axum::response::Response {
    (
        code,
        [(header::CONTENT_TYPE, "application/json")],
        v.to_string(),
    )
        .into_response()
}

async fn api_status(State(st): State<Arc<AppState>>, headers: HeaderMap) -> impl IntoResponse {
    if let Some(r) = unauthorized(&st, &headers) {
        return r;
    }
    let temp = std::fs::read_to_string("/sys/class/thermal/thermal_zone0/temp")
        .ok()
        .and_then(|s| s.trim().parse::<f64>().ok())
        .map(|t| t / 1000.0);
    json(
        StatusCode::OK,
        serde_json::json!({
            "publishing": st.is_running(),
            "listeners": st.sessions.lock().unwrap().len(),
            "cpu_temp_c": temp,
            "uptime_s": st.started.elapsed().as_secs(),
            "version": st.version,
            "frame": { "rate": SAMPLE_RATE, "samples": FRAME_SAMPLES, "pt": OPUS_PT },
        }),
    )
}

async fn api_level(State(st): State<Arc<AppState>>, headers: HeaderMap) -> impl IntoResponse {
    if let Some(r) = unauthorized(&st, &headers) {
        return r;
    }
    let ts = st.level_ts.load(Ordering::Relaxed);
    let peak = if ts == 0 {
        -1.0
    } else {
        f32::from_bits(st.level_peak.load(Ordering::Relaxed))
    };
    json(StatusCode::OK, serde_json::json!({ "peak": peak, "ts": ts }))
}

async fn api_logs(State(st): State<Arc<AppState>>, headers: HeaderMap) -> impl IntoResponse {
    if let Some(r) = unauthorized(&st, &headers) {
        return r;
    }
    let lines: Vec<String> = st.events.lock().unwrap().iter().cloned().collect();
    json(
        StatusCode::OK,
        serde_json::json!({ "ok": true, "lines": lines, "source": "ring" }),
    )
}

async fn api_publish(
    State(st): State<Arc<AppState>>,
    Path(action): Path<String>,
    headers: HeaderMap,
) -> impl IntoResponse {
    if let Some(r) = unauthorized(&st, &headers) {
        return r;
    }
    match action.as_str() {
        "start" => {
            st.running.store(true, Ordering::Relaxed);
            st.log("publish: start (api)");
            json(StatusCode::OK, serde_json::json!({ "ok": true }))
        }
        "stop" => {
            st.running.store(false, Ordering::Relaxed);
            st.log("publish: stop (api)");
            json(StatusCode::OK, serde_json::json!({ "ok": true }))
        }
        "restart" => {
            st.running.store(false, Ordering::Relaxed);
            tokio::time::sleep(Duration::from_millis(300)).await;
            st.running.store(true, Ordering::Relaxed);
            st.log("publish: restart (api)");
            json(StatusCode::OK, serde_json::json!({ "ok": true }))
        }
        _ => json(
            StatusCode::NOT_FOUND,
            serde_json::json!({ "error": "unknown action (start/stop/restart)" }),
        ),
    }
}

mod audio;
mod hub;

use anyhow::{Context, Result};
use clap::Parser;
use std::net::SocketAddr;

#[derive(Parser, Debug)]
#[command(
    name = "rhemacastd",
    about = "rhemacast live audio broadcast — mic/tone -> Opus -> WebRTC fan-out (+ admin API + web UI)"
)]
struct Args {
    /// HTTP port: WHEP signaling, /api/*, listen.html + admin.html
    #[arg(long, default_value_t = 8080)]
    port: u16,
    /// Test mode: synthesize a sine tone at this Hz instead of opening the mic
    #[arg(long)]
    tone: Option<f32>,
    /// Mic: substring match on input device name (default: system default input)
    #[arg(long)]
    device: Option<String>,
    /// List input devices and exit
    #[arg(long)]
    list_devices: bool,
    /// Opus bitrate, bits/sec
    #[arg(long, default_value_t = 32000)]
    bitrate: i32,
    /// Also forward raw RTP/Opus packets over UDP (future ESP32 receivers)
    #[arg(long)]
    udp_out: Option<SocketAddr>,
}

#[tokio::main(flavor = "multi_thread")]
async fn main() -> Result<()> {
    let args = Args::parse();
    if args.list_devices {
        return audio::list_devices();
    }
    let state = hub::AppState::new(args.udp_out);
    state.log("rhemacastd starting");

    // Capture + encode runs on its own OS thread (all blocking I/O).
    let cfg = audio::SourceConfig {
        tone: args.tone,
        device: args.device,
        bitrate: args.bitrate,
    };
    let st = state.clone();
    std::thread::Builder::new()
        .name("source".into())
        .spawn(move || {
            if let Err(e) = audio::run_source(cfg, st) {
                eprintln!("source fatal: {e:#}");
                std::process::exit(1);
            }
        })
        .context("spawn source thread")?;

    hub::serve(state, args.port).await
}

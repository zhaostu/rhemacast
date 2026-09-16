//! Audio source: USB mic (cpal) or synthesized test tone.
//! Produces 960-sample (20ms) mono f32 frames at 48kHz, Opus-encodes them,
//! and fans the RTP packets out over a broadcast channel (WebRTC sessions)
//! plus an optional raw UDP socket (future ESP32 receivers).

use crate::hub::AppState;
use anyhow::{Context, Result};
use bytes::Bytes;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use std::net::UdpSocket;
use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};
use webrtc::rtp::header::Header;
use webrtc::rtp::packet::Packet;
use webrtc::util::Marshal;

pub const SAMPLE_RATE: u32 = 48000;
pub const FRAME_SAMPLES: usize = 960; // 20ms @ 48kHz
pub const OPUS_PT: u8 = 111;

pub struct SourceConfig {
    pub tone: Option<f32>,
    pub device: Option<String>,
    pub bitrate: i32,
}

pub fn list_devices() -> Result<()> {
    let host = cpal::default_host();
    println!("input devices:");
    for dev in host.input_devices().context("no input devices")? {
        println!("- {}", dev_name(&dev));
    }
    Ok(())
}

fn dev_name(dev: &cpal::Device) -> String {
    dev.description()
        .map(|d| d.name().to_owned())
        .unwrap_or_else(|_| "<unnamed>".into())
}

struct Emitter {
    enc: audiopus::coder::Encoder,
    out: Vec<u8>,
    ssrc: u32,
    seq: u16,
    ts: u32,
    udp: Option<UdpSocket>,
}

impl Emitter {
    fn new(bitrate: i32, udp_out: Option<std::net::SocketAddr>) -> Result<Self> {
        let mut enc = audiopus::coder::Encoder::new(
            audiopus::SampleRate::Hz48000,
            audiopus::Channels::Mono,
            audiopus::Application::Voip,
        )
        .context("opus encoder init")?;
        enc.set_bitrate(audiopus::Bitrate::BitsPerSecond(bitrate))
            .context("opus set_bitrate")?;
        let ssrc = (SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0x1234) as u32)
            | 0x1000;
        let udp = match udp_out {
            Some(_) => Some(UdpSocket::bind("0.0.0.0:0").context("udp bind")?),
            None => None,
        };
        Ok(Self {
            enc,
            out: vec![0u8; 4000],
            ssrc,
            seq: 0,
            ts: 0,
            udp,
        })
    }

    fn emit(&mut self, st: &AppState, udp_target: Option<std::net::SocketAddr>, pcm: &[f32]) -> Result<()> {
        debug_assert_eq!(pcm.len(), FRAME_SAMPLES);
        let peak = pcm.iter().fold(0f32, |m, &s| m.max(s.abs()));
        st.set_level(peak);
        let n = self.enc.encode_float(pcm, &mut self.out)?;
        let pkt = Packet {
            header: Header {
                version: 2,
                payload_type: OPUS_PT,
                sequence_number: self.seq,
                timestamp: self.ts,
                ssrc: self.ssrc,
                ..Default::default()
            },
            payload: Bytes::copy_from_slice(&self.out[..n]),
        };
        self.seq = self.seq.wrapping_add(1);
        self.ts = self.ts.wrapping_add(FRAME_SAMPLES as u32);
        let _ = st.frames.send(pkt.clone()); // Err = no listeners yet; fine
        if let (Some(sock), Some(target)) = (&self.udp, udp_target) {
            if let Ok(raw) = pkt.marshal() {
                let _ = sock.send_to(&raw, target);
            }
        }
        Ok(())
    }
}

pub fn run_source(cfg: SourceConfig, st: Arc<AppState>) -> Result<()> {
    match cfg.tone {
        Some(freq) => {
            st.log(&format!("source: test tone {freq}Hz"));
            tone_loop(cfg.bitrate, st, freq)
        }
        None => {
            st.log("source: microphone");
            mic_loop(cfg, st)
        }
    }
}

// --- Test tone: sine at `freq` Hz, paced to realtime ---

fn tone_loop(bitrate: i32, st: Arc<AppState>, freq: f32) -> Result<()> {
    let udp_target = st.udp_out;
    let mut em = Emitter::new(bitrate, udp_target)?;
    let mut phase = 0f32;
    let step = freq / SAMPLE_RATE as f32;
    let mut frame = [0f32; FRAME_SAMPLES];
    let mut next = std::time::Instant::now();
    loop {
        if !st.is_running() {
            std::thread::sleep(std::time::Duration::from_millis(50));
            next = std::time::Instant::now();
            continue;
        }
        for s in frame.iter_mut() {
            *s = (phase * std::f32::consts::TAU).sin() * 0.3;
            phase = (phase + step) % 1.0;
        }
        em.emit(&st, udp_target, &frame)?;
        next += std::time::Duration::from_millis(20);
        let now = std::time::Instant::now();
        if next > now {
            std::thread::sleep(next - now);
        } else {
            next = now; // fell behind; don't spiral
        }
    }
}

// --- Microphone via cpal ---

fn mic_loop(cfg: SourceConfig, st: Arc<AppState>) -> Result<()> {
    let udp_target = st.udp_out;
    let host = cpal::default_host();
    let device = match &cfg.device {
        Some(want) => host
            .input_devices()
            .context("no input devices")?
            .find(|d| dev_name(d).contains(want.as_str()))
            .context(format!("no input device matching '{want}'"))?,
        None => host.default_input_device().context("no default input device")?,
    };
    st.log(&format!("mic: {}", dev_name(&device)));

    // Prefer 48kHz mono; otherwise take the default and convert.
    let supported: Vec<_> = device
        .supported_input_configs()
        .context("mic configs")?
        .collect();
    // Prefer 48kHz mono; among those, prefer the highest bit depth —
    // an 8-bit mode (I8/U8) sounds hissy next to F32/I16.
    fn format_rank(f: cpal::SampleFormat) -> u8 {
        match f {
            cpal::SampleFormat::F32 => 0,
            cpal::SampleFormat::I32 => 1,
            cpal::SampleFormat::I16 => 2,
            cpal::SampleFormat::F64 => 3,
            cpal::SampleFormat::U16 => 4,
            cpal::SampleFormat::U8 => 5,
            cpal::SampleFormat::I8 => 6,
            _ => 7,
        }
    }
    let (stream_cfg, in_rate, in_ch): (cpal::SupportedStreamConfig, u32, usize) =
        match supported
            .iter()
            .filter(|c| {
                c.channels() == 1
                    && c.min_sample_rate() <= SAMPLE_RATE
                    && c.max_sample_rate() >= SAMPLE_RATE
            })
            .min_by_key(|c| format_rank(c.sample_format()))
        {
            Some(c) => (c.clone().with_sample_rate(SAMPLE_RATE), SAMPLE_RATE, 1),
            None => {
                let d = device.default_input_config().context("mic default config")?;
                (d.clone(), d.sample_rate(), d.channels() as usize)
            }
        };
    st.log(&format!(
        "mic format: {}ch @ {}Hz {:?} (converts to mono 48kHz)",
        in_ch,
        in_rate,
        stream_cfg.sample_format()
    ));
    // Callback path: downmix -> linear-resample -> 480-sample chunks.
    let (tx, rx) = std::sync::mpsc::sync_channel::<Vec<f32>>(64);
    let mut conv = Converter::new(in_rate, in_ch);
    let build = |format: cpal::SampleFormat| -> Result<cpal::Stream> {
        let err_fn = |e| eprintln!("mic stream error: {e}");
        let sc: cpal::StreamConfig = stream_cfg.config();
        match format {
            cpal::SampleFormat::F32 => device
                .build_input_stream(
                    sc.clone(),
                    move |data: &[f32], _| push_samples(&mut conv, &tx, data.iter().map(|&s| s)),
                    err_fn,
                    None,
                )
                .context("build mic stream"),
            cpal::SampleFormat::I8 => device
                .build_input_stream(
                    sc.clone(),
                    move |data: &[i8], _| {
                        push_samples(&mut conv, &tx, data.iter().map(|&s| s as f32 / 128.0))
                    },
                    err_fn,
                    None,
                )
                .context("build mic stream"),
            cpal::SampleFormat::I16 => device
                .build_input_stream(
                    sc.clone(),
                    move |data: &[i16], _| {
                        push_samples(&mut conv, &tx, data.iter().map(|&s| s as f32 / 32768.0))
                    },
                    err_fn,
                    None,
                )
                .context("build mic stream"),
            cpal::SampleFormat::U16 => device
                .build_input_stream(
                    sc.clone(),
                    move |data: &[u16], _| {
                        push_samples(&mut conv, &tx, data.iter().map(|&s| s as f32 / 65535.0 * 2.0 - 1.0))
                    },
                    err_fn,
                    None,
                )
                .context("build mic stream"),
            cpal::SampleFormat::I32 => device
                .build_input_stream(
                    sc.clone(),
                    move |data: &[i32], _| {
                        push_samples(&mut conv, &tx, data.iter().map(|&s| {
                            s as f32 / 2_147_483_648.0
                        }))
                    },
                    err_fn,
                    None,
                )
                .context("build mic stream"),
            cpal::SampleFormat::U8 => device
                .build_input_stream(
                    sc.clone(),
                    move |data: &[u8], _| {
                        push_samples(&mut conv, &tx, data.iter().map(|&s| {
                            s as f32 / 255.0 * 2.0 - 1.0
                        }))
                    },
                    err_fn,
                    None,
                )
                .context("build mic stream"),
            cpal::SampleFormat::F64 => device
                .build_input_stream(
                    sc.clone(),
                    move |data: &[f64], _| {
                        push_samples(&mut conv, &tx, data.iter().map(|&s| s as f32))
                    },
                    err_fn,
                    None,
                )
                .context("build mic stream"),
            f => anyhow::bail!("unsupported mic sample format: {f:?}"),
        }
    };
    let stream = build(stream_cfg.sample_format())?;
    stream.play().context("mic play")?;

    let mut em = Emitter::new(cfg.bitrate, udp_target)?;
    let mut pending: Vec<f32> = Vec::with_capacity(FRAME_SAMPLES * 2);
    let mut was_running = true;
    loop {
        let running = st.is_running();
        if running != was_running {
            if running {
                stream.play().ok();
                st.log("publish: started");
            } else {
                stream.pause().ok();
                pending.clear();
                st.log("publish: stopped");
            }
            was_running = running;
        }
        if !running {
            std::thread::sleep(std::time::Duration::from_millis(50));
            continue;
        }
        match rx.recv_timeout(std::time::Duration::from_millis(200)) {
            Ok(chunk) => {
                pending.extend_from_slice(&chunk);
                while pending.len() >= FRAME_SAMPLES {
                    let frame: Vec<f32> = pending.drain(..FRAME_SAMPLES).collect();
                    em.emit(&st, udp_target, &frame)?;
                }
            }
            Err(std::sync::mpsc::RecvTimeoutError::Timeout) => continue,
            Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => {
                anyhow::bail!("mic stream ended")
            }
        }
    }
}

/// Mono downmix + linear resample to 48kHz, flushed in 480-sample chunks.
struct Converter {
    step: f64, // input samples per output sample
    pos: f64,  // position of next output within current input segment [prev, x]
    prev: f32,
    in_ch: usize,
    buf: Vec<f32>,
}

impl Converter {
    fn new(in_rate: u32, in_ch: usize) -> Self {
        Self {
            step: in_rate as f64 / SAMPLE_RATE as f64,
            pos: 0.0,
            prev: 0.0,
            in_ch,
            buf: Vec::with_capacity(480),
        }
    }

    /// Feed one mono input sample; completed 480-chunks are appended to `outs`.
    fn feed(&mut self, x: f32, outs: &mut Vec<Vec<f32>>) {
        while self.pos < 1.0 {
            let t = self.pos as f32;
            self.buf.push(self.prev + (x - self.prev) * t);
            if self.buf.len() == 480 {
                outs.push(std::mem::replace(&mut self.buf, Vec::with_capacity(480)));
            }
            self.pos += self.step;
        }
        self.pos -= 1.0;
        self.prev = x;
    }
}

fn push_samples(
    conv: &mut Converter,
    tx: &std::sync::mpsc::SyncSender<Vec<f32>>,
    samples: impl Iterator<Item = f32>,
) {
    let mut outs: Vec<Vec<f32>> = Vec::new();
    // downmix interleaved input to mono first
    let ch = conv.in_ch.max(1);
    let mut acc = 0f32;
    let mut n = 0;
    for s in samples {
        acc += s;
        n += 1;
        if n == ch {
            conv.feed(acc / ch as f32, &mut outs);
            acc = 0.0;
            n = 0;
        }
    }
    for chunk in outs {
        let _ = tx.try_send(chunk); // drop on overflow: stay realtime
    }
}

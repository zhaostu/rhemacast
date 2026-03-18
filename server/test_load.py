#!/usr/bin/env python3
"""Load test: simulate N concurrent WebRTC clients connecting to the Rhemacast server."""

import argparse
import asyncio
import json
import logging
import time

import aiohttp
from aiortc import RTCConfiguration, RTCPeerConnection, RTCSessionDescription

logging.basicConfig(level=logging.WARNING)
logger = logging.getLogger(__name__)


async def run_client(
    client_id: int,
    url: str,
    duration: float,
    results: list,
) -> None:
    result = {
        "id": client_id,
        "connected": False,
        "connect_time": None,
        "frames": 0,
        "error": None,
    }
    start = time.monotonic()
    frame_count = 0

    pc = RTCPeerConnection(configuration=RTCConfiguration(iceServers=[]))
    pc.addTransceiver("audio", direction="recvonly")

    @pc.on("track")
    async def on_track(track):
        nonlocal frame_count
        while True:
            try:
                await asyncio.wait_for(track.recv(), timeout=1.0)
                frame_count += 1
            except (asyncio.TimeoutError, Exception):
                break

    try:
        offer = await pc.createOffer()
        await pc.setLocalDescription(offer)

        async with aiohttp.ClientSession() as session:
            async with session.ws_connect(url) as ws:
                await ws.send_json(
                    {"type": "offer", "sdp": pc.localDescription.sdp}
                )

                raw = await asyncio.wait_for(ws.receive_json(), timeout=10.0)
                if raw.get("type") != "answer":
                    raise ValueError(f"Expected answer, got {raw.get('type')}")

                await pc.setRemoteDescription(
                    RTCSessionDescription(sdp=raw["sdp"], type="answer")
                )

                result["connected"] = True
                result["connect_time"] = time.monotonic() - start
                logger.info("Client %d connected in %.2fs", client_id, result["connect_time"])

                await asyncio.sleep(duration)

    except Exception as exc:
        result["error"] = str(exc)
        logger.warning("Client %d failed: %s", client_id, exc)
    finally:
        result["frames"] = frame_count
        await pc.close()

    results.append(result)


async def main() -> int:
    parser = argparse.ArgumentParser(description="Rhemacast load test")
    parser.add_argument(
        "--clients", type=int, default=5, help="Number of concurrent clients (default: 5)"
    )
    parser.add_argument(
        "--duration", type=int, default=30, help="Duration each client stays connected in seconds (default: 30)"
    )
    parser.add_argument(
        "--url", default="ws://192.168.4.1:8080/ws", help="WebSocket URL of the server"
    )
    args = parser.parse_args()

    print(f"Starting load test: {args.clients} clients, {args.duration}s duration")
    print(f"Server: {args.url}")
    print()

    results: list = []
    tasks = [
        asyncio.create_task(run_client(i, args.url, args.duration, results))
        for i in range(args.clients)
    ]
    await asyncio.gather(*tasks, return_exceptions=True)

    connected = sum(1 for r in results if r["connected"])
    connect_times = [r["connect_time"] for r in results if r["connect_time"] is not None]
    avg_connect_time = sum(connect_times) / len(connect_times) if connect_times else 0.0
    total_frames = sum(r["frames"] for r in results)
    avg_fps = total_frames / args.duration / max(connected, 1) if connected else 0.0

    print("--- Results ---")
    print(f"{connected}/{args.clients} clients connected")
    if connect_times:
        print(f"Avg connect time: {avg_connect_time:.2f}s")
    print(f"Avg frame rate: {avg_fps:.1f} fps per client")
    print(f"Duration: {args.duration}s")

    if connected < args.clients:
        errors = [r["error"] for r in results if r.get("error")]
        for err in errors:
            print(f"  Error: {err}")

    return 0 if connected == args.clients else 1


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))

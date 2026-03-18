import asyncio
import json
import logging
import uuid

import aiohttp.web
from aiortc import RTCConfiguration, RTCPeerConnection, RTCSessionDescription

from audio_track import MicrophoneAudioTrack
from broadcast import BroadcastManager

logger = logging.getLogger(__name__)


async def ws_handler(request: aiohttp.web.Request) -> aiohttp.web.WebSocketResponse:
    broadcast_manager: BroadcastManager = request.app["broadcast_manager"]

    ws = aiohttp.web.WebSocketResponse()
    await ws.prepare(request)

    peer_id = str(uuid.uuid4())
    peer_queue: asyncio.Queue = asyncio.Queue(maxsize=10)
    pc = RTCPeerConnection(configuration=RTCConfiguration(iceServers=[]))

    broadcast_manager.add_peer(peer_id, peer_queue)
    logger.info("Peer connected: %s", peer_id)

    try:
        track = MicrophoneAudioTrack(peer_queue)
        pc.addTrack(track)

        # Receive offer
        msg_text = await ws.receive_str()
        msg = json.loads(msg_text)
        if msg.get("type") != "offer":
            logger.error("Expected offer, got: %s", msg.get("type"))
            return ws

        await pc.setRemoteDescription(
            RTCSessionDescription(sdp=msg["sdp"], type="offer")
        )
        answer = await pc.createAnswer()
        await pc.setLocalDescription(answer)

        await ws.send_json({"type": "answer", "sdp": pc.localDescription.sdp})
        logger.info("Answer sent to peer: %s", peer_id)

        # Keep WS open; handle any further messages (e.g. ICE candidates)
        async for msg in ws:
            if msg.type == aiohttp.WSMsgType.TEXT:
                try:
                    data = json.loads(msg.data)
                    logger.debug("Message from peer %s: %s", peer_id, data)
                except json.JSONDecodeError:
                    pass
            elif msg.type in (aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSE):
                break

    except Exception:
        logger.exception("Error in ws_handler for peer %s", peer_id)
    finally:
        broadcast_manager.remove_peer(peer_id)
        await pc.close()
        logger.info("Peer disconnected: %s", peer_id)

    return ws

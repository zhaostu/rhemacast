import asyncio
import sys
import os

import pytest
from aiohttp import web
from aiohttp.test_utils import TestClient, TestServer
from aiortc import RTCConfiguration, RTCPeerConnection

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from broadcast import BroadcastManager
from signaling import ws_handler


def make_app(broadcast_manager: BroadcastManager) -> web.Application:
    app = web.Application()
    app["broadcast_manager"] = broadcast_manager

    async def handler(request):
        return await ws_handler(request)

    app.router.add_get("/ws", handler)
    return app


async def make_offer_sdp() -> str:
    """Generate a real SDP offer using aiortc (no setLocalDescription needed)."""
    pc = RTCPeerConnection(configuration=RTCConfiguration(iceServers=[]))
    pc.addTransceiver("audio", direction="recvonly")
    offer = await pc.createOffer()
    sdp = offer.sdp
    await pc.close()
    return sdp


@pytest.mark.asyncio
async def test_peer_registered_during_connection():
    """Peer should appear in broadcast_manager._peers while connected."""
    bm = BroadcastManager()
    app = make_app(bm)

    offer_sdp = await make_offer_sdp()

    async with TestClient(TestServer(app)) as client:
        ws = await client.ws_connect("/ws")
        await ws.send_json({"type": "offer", "sdp": offer_sdp})

        msg = await asyncio.wait_for(ws.receive_json(), timeout=10.0)
        assert msg["type"] == "answer"

        # Peer should be registered while WS is open
        assert len(bm._peers) == 1

        await ws.close()


@pytest.mark.asyncio
async def test_peer_cleaned_up_after_disconnect():
    """Peer should be removed from broadcast_manager after WS closes."""
    bm = BroadcastManager()
    app = make_app(bm)

    offer_sdp = await make_offer_sdp()

    async with TestClient(TestServer(app)) as client:
        ws = await client.ws_connect("/ws")
        await ws.send_json({"type": "offer", "sdp": offer_sdp})

        msg = await asyncio.wait_for(ws.receive_json(), timeout=10.0)
        assert msg["type"] == "answer"

        await ws.close()
        # Give handler a moment to run cleanup
        await asyncio.sleep(0.2)

        assert len(bm._peers) == 0


@pytest.mark.asyncio
async def test_answer_response_format():
    """Server should respond with JSON containing type=answer and sdp."""
    bm = BroadcastManager()
    app = make_app(bm)

    offer_sdp = await make_offer_sdp()

    async with TestClient(TestServer(app)) as client:
        ws = await client.ws_connect("/ws")
        await ws.send_json({"type": "offer", "sdp": offer_sdp})

        msg = await asyncio.wait_for(ws.receive_json(), timeout=10.0)

        assert msg["type"] == "answer"
        assert "sdp" in msg
        assert isinstance(msg["sdp"], str)
        assert len(msg["sdp"]) > 0

        await ws.close()


@pytest.mark.asyncio
async def test_peer_cleaned_up_on_exception():
    """Peer should be removed from broadcast_manager even if WS closed prematurely (before offer)."""
    bm = BroadcastManager()
    app = make_app(bm)

    async with TestClient(TestServer(app)) as client:
        ws = await client.ws_connect("/ws")
        # Close without sending an offer — causes handler to hit an exception on receive_str()
        await ws.close()
        # Give handler time to run finally cleanup
        await asyncio.sleep(0.3)

        assert len(bm._peers) == 0

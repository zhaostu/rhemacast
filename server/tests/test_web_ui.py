import asyncio
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

import pytest
from aiohttp.test_utils import TestClient, TestServer

from server import create_app
from broadcast import BroadcastManager


@pytest.fixture
def broadcast_manager():
    return BroadcastManager()


@pytest.fixture
def app(broadcast_manager):
    return create_app(broadcast_manager=broadcast_manager)


@pytest.mark.asyncio
async def test_index_handler_status(app):
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/")
        assert resp.status == 200


@pytest.mark.asyncio
async def test_index_handler_content_type(app):
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/")
        assert "text/html" in resp.content_type


@pytest.mark.asyncio
async def test_index_handler_contains_rhemacast(app):
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/")
        text = await resp.text()
        assert "Rhemacast" in text


@pytest.mark.asyncio
async def test_index_handler_contains_canvas(app):
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/")
        text = await resp.text()
        assert "<canvas" in text


@pytest.mark.asyncio
async def test_index_handler_contains_ws_ui(app):
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/")
        text = await resp.text()
        assert "ws-ui" in text


@pytest.mark.asyncio
async def test_ws_ui_handler_receives_message(app):
    async with TestClient(TestServer(app)) as client:
        ws = await client.ws_connect("/ws-ui")
        msg = await asyncio.wait_for(ws.receive_json(), timeout=5.0)
        assert msg is not None
        await ws.close()
        await asyncio.sleep(0.1)


@pytest.mark.asyncio
async def test_ws_ui_handler_message_keys(app):
    async with TestClient(TestServer(app)) as client:
        ws = await client.ws_connect("/ws-ui")
        msg = await asyncio.wait_for(ws.receive_json(), timeout=5.0)
        assert "peer_count" in msg
        assert "streaming" in msg
        assert "vu_db" in msg
        await ws.close()
        await asyncio.sleep(0.1)


@pytest.mark.asyncio
async def test_ws_ui_handler_message_types(app):
    async with TestClient(TestServer(app)) as client:
        ws = await client.ws_connect("/ws-ui")
        msg = await asyncio.wait_for(ws.receive_json(), timeout=5.0)
        assert isinstance(msg["peer_count"], int)
        assert isinstance(msg["streaming"], bool)
        assert isinstance(msg["vu_db"], float)
        await ws.close()
        await asyncio.sleep(0.1)

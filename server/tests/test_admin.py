import asyncio
import struct
import sys
import os

import pytest
from aiohttp.test_utils import TestClient, TestServer

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from server import create_app
from broadcast import BroadcastManager


def make_audio_bytes(value: int, n_samples: int = 960) -> bytes:
    return struct.pack(f"<{n_samples}h", *([value] * n_samples))


# ---------- broadcast volume / mute ----------

@pytest.mark.asyncio
async def test_distribute_muted_does_not_reach_peers():
    bm = BroadcastManager()
    q = asyncio.Queue()
    bm.add_peer("a", q)
    bm.muted = True
    await bm.distribute(make_audio_bytes(100))
    assert q.empty()


@pytest.mark.asyncio
async def test_distribute_muted_still_appends_recent_frames():
    bm = BroadcastManager()
    bm.muted = True
    data = make_audio_bytes(100)
    await bm.distribute(data)
    assert len(bm._recent_frames) == 1


@pytest.mark.asyncio
async def test_distribute_volume_gain_applied():
    bm = BroadcastManager()
    q = asyncio.Queue()
    bm.add_peer("a", q)
    bm.volume_gain = 0.5
    data = make_audio_bytes(1000)
    await bm.distribute(data)
    result = q.get_nowait()
    import numpy as np
    samples = np.frombuffer(result, dtype=np.int16)
    assert all(abs(s) <= 500 + 1 for s in samples)


@pytest.mark.asyncio
async def test_distribute_volume_gain_1_passes_unchanged():
    bm = BroadcastManager()
    q = asyncio.Queue()
    bm.add_peer("a", q)
    bm.volume_gain = 1.0
    data = make_audio_bytes(100)
    await bm.distribute(data)
    assert q.get_nowait() == data


# ---------- admin PIN auth ----------

@pytest.mark.asyncio
async def test_admin_no_pin_allows_access():
    app = create_app(admin_pin=None)
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/admin/clients")
        assert resp.status == 200


@pytest.mark.asyncio
async def test_admin_pin_required_without_header():
    app = create_app(admin_pin="1234")
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/admin/clients")
        assert resp.status == 401


@pytest.mark.asyncio
async def test_admin_pin_wrong_header():
    app = create_app(admin_pin="1234")
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/admin/clients", headers={"X-Admin-PIN": "0000"})
        assert resp.status == 401


@pytest.mark.asyncio
async def test_admin_pin_correct_header():
    app = create_app(admin_pin="1234")
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/admin/clients", headers={"X-Admin-PIN": "1234"})
        assert resp.status == 200


@pytest.mark.asyncio
async def test_admin_clients_empty():
    app = create_app()
    async with TestClient(TestServer(app)) as client:
        resp = await client.get("/admin/clients")
        data = await resp.json()
        assert data == []


@pytest.mark.asyncio
async def test_admin_kick_unknown_peer():
    app = create_app()
    async with TestClient(TestServer(app)) as client:
        resp = await client.post("/admin/kick/nonexistent-peer-id")
        assert resp.status == 404


# ---------- admin volume ----------

@pytest.mark.asyncio
async def test_admin_volume_set():
    bm = BroadcastManager()
    app = create_app(broadcast_manager=bm)
    async with TestClient(TestServer(app)) as client:
        resp = await client.post("/admin/volume", json={"level": 0.5})
        assert resp.status == 200
        data = await resp.json()
        assert data["volume"] == 0.5
        assert bm.volume_gain == 0.5


@pytest.mark.asyncio
async def test_admin_volume_out_of_range():
    app = create_app()
    async with TestClient(TestServer(app)) as client:
        resp = await client.post("/admin/volume", json={"level": 1.5})
        assert resp.status == 400


@pytest.mark.asyncio
async def test_admin_volume_missing_field():
    app = create_app()
    async with TestClient(TestServer(app)) as client:
        resp = await client.post("/admin/volume", json={})
        assert resp.status == 400


# ---------- admin mute ----------

@pytest.mark.asyncio
async def test_admin_mute_true():
    bm = BroadcastManager()
    app = create_app(broadcast_manager=bm)
    async with TestClient(TestServer(app)) as client:
        resp = await client.post("/admin/mute", json={"muted": True})
        assert resp.status == 200
        data = await resp.json()
        assert data["muted"] is True
        assert bm.muted is True


@pytest.mark.asyncio
async def test_admin_mute_false():
    bm = BroadcastManager()
    bm.muted = True
    app = create_app(broadcast_manager=bm)
    async with TestClient(TestServer(app)) as client:
        resp = await client.post("/admin/mute", json={"muted": False})
        assert resp.status == 200
        assert bm.muted is False


@pytest.mark.asyncio
async def test_admin_mute_invalid_type():
    app = create_app()
    async with TestClient(TestServer(app)) as client:
        resp = await client.post("/admin/mute", json={"muted": "yes"})
        assert resp.status == 400


# ---------- ws-ui includes new fields ----------

@pytest.mark.asyncio
async def test_ws_ui_includes_muted_volume_clients():
    app = create_app()
    async with TestClient(TestServer(app)) as client:
        ws = await client.ws_connect("/ws-ui")
        msg = await asyncio.wait_for(ws.receive_json(), timeout=5.0)
        assert "muted" in msg
        assert "volume" in msg
        assert "clients" in msg
        assert isinstance(msg["muted"], bool)
        assert isinstance(msg["volume"], float)
        assert isinstance(msg["clients"], list)
        await ws.close()
        await asyncio.sleep(0.1)


# ---------- parse_args --admin-pin and --echo-cancel ----------

def test_parse_args_echo_cancel_default():
    from server import parse_args
    args = parse_args([])
    assert args.echo_cancel is False


def test_parse_args_echo_cancel_flag():
    from server import parse_args
    args = parse_args(["--echo-cancel"])
    assert args.echo_cancel is True


def test_parse_args_admin_pin_default():
    from server import parse_args
    args = parse_args([])
    assert args.admin_pin is None


def test_parse_args_admin_pin_value():
    from server import parse_args
    args = parse_args(["--admin-pin", "9999"])
    assert args.admin_pin == "9999"

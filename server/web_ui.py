import asyncio
import logging
import os

import aiohttp.web

from broadcast import BroadcastManager

logger = logging.getLogger(__name__)

_STATIC_DIR = os.path.join(os.path.dirname(__file__), "static")


async def index_handler(request: aiohttp.web.Request) -> aiohttp.web.Response:
    index_path = os.path.join(_STATIC_DIR, "index.html")
    with open(index_path, "r", encoding="utf-8") as f:
        content = f.read()
    return aiohttp.web.Response(text=content, content_type="text/html")


async def ws_ui_handler(request: aiohttp.web.Request) -> aiohttp.web.WebSocketResponse:
    broadcast_manager: BroadcastManager = request.app["broadcast_manager"]
    registry: dict = request.app.get("client_registry", {})

    ws = aiohttp.web.WebSocketResponse()
    await ws.prepare(request)

    try:
        while not ws.closed:
            clients = [
                {"peer_id": info["peer_id"], "ip_address": info["ip_address"], "connected_at": info["connected_at"]}
                for info in registry.values()
            ]
            stats = {
                "peer_count": len(broadcast_manager._peers),
                "streaming": broadcast_manager.streaming,
                "vu_db": broadcast_manager.get_vu_db(),
                "muted": broadcast_manager.muted,
                "volume": broadcast_manager.volume_gain,
                "clients": clients,
            }
            try:
                await ws.send_json(stats)
            except Exception:
                break
            try:
                await asyncio.wait_for(ws.receive(), timeout=1.0)
                # client sent a message or close frame — exit
                break
            except asyncio.TimeoutError:
                pass  # no message yet, loop again
    except Exception:
        logger.debug("ws_ui_handler disconnected")
    finally:
        if not ws.closed:
            await ws.close()

    return ws


async def admin_clients_handler(request: aiohttp.web.Request) -> aiohttp.web.Response:
    registry: dict = request.app.get("client_registry", {})
    clients = [
        {"peer_id": info["peer_id"], "ip_address": info["ip_address"], "connected_at": info["connected_at"]}
        for info in registry.values()
    ]
    return aiohttp.web.json_response(clients)


async def admin_kick_handler(request: aiohttp.web.Request) -> aiohttp.web.Response:
    peer_id = request.match_info["peer_id"]
    registry: dict = request.app.get("client_registry", {})
    if peer_id not in registry:
        raise aiohttp.web.HTTPNotFound(reason="Peer not found")
    await registry[peer_id]["ws"].close()
    return aiohttp.web.json_response({"kicked": peer_id})


async def admin_volume_handler(request: aiohttp.web.Request) -> aiohttp.web.Response:
    bm: BroadcastManager = request.app["broadcast_manager"]
    try:
        body = await request.json()
    except Exception:
        raise aiohttp.web.HTTPBadRequest(reason="Invalid JSON")
    level = body.get("level")
    if level is None or not isinstance(level, (int, float)) or not (0.0 <= level <= 1.0):
        raise aiohttp.web.HTTPBadRequest(reason="level must be a float 0.0-1.0")
    bm.volume_gain = float(level)
    return aiohttp.web.json_response({"volume": bm.volume_gain})


async def admin_mute_handler(request: aiohttp.web.Request) -> aiohttp.web.Response:
    bm: BroadcastManager = request.app["broadcast_manager"]
    try:
        body = await request.json()
    except Exception:
        raise aiohttp.web.HTTPBadRequest(reason="Invalid JSON")
    muted = body.get("muted")
    if not isinstance(muted, bool):
        raise aiohttp.web.HTTPBadRequest(reason="muted must be a boolean")
    bm.muted = muted
    return aiohttp.web.json_response({"muted": bm.muted})

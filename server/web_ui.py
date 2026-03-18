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

    ws = aiohttp.web.WebSocketResponse()
    await ws.prepare(request)

    try:
        while not ws.closed:
            stats = {
                "peer_count": len(broadcast_manager._peers),
                "streaming": broadcast_manager.streaming,
                "vu_db": broadcast_manager.get_vu_db(),
            }
            await ws.send_json(stats)
            await asyncio.sleep(1.0)
    except Exception:
        logger.debug("ws_ui_handler disconnected")
    finally:
        if not ws.closed:
            await ws.close()

    return ws

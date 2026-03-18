import argparse
import asyncio
import logging

import aiohttp.web
import sounddevice

from broadcast import BroadcastManager
from signaling import ws_handler
from web_ui import index_handler, ws_ui_handler

logger = logging.getLogger(__name__)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Rhemacast server")
    parser.add_argument("--device", type=int, default=None,
                        help="sounddevice device index (default: system default)")
    parser.add_argument("--host", default="0.0.0.0",
                        help="host to bind (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080,
                        help="port to bind (default: 8080)")
    return parser.parse_args(argv)


def create_app(broadcast_manager=None) -> aiohttp.web.Application:
    if broadcast_manager is None:
        broadcast_manager = BroadcastManager()

    app = aiohttp.web.Application()
    app["broadcast_manager"] = broadcast_manager

    async def ws_handler_wrapper(request):
        return await ws_handler(request, broadcast_manager)

    async def ws_ui_handler_wrapper(request):
        return await ws_ui_handler(request, broadcast_manager)

    app.router.add_get("/", index_handler)
    app.router.add_get("/ws", ws_handler_wrapper)
    app.router.add_get("/ws-ui", ws_ui_handler_wrapper)

    import os
    static_dir = os.path.join(os.path.dirname(__file__), "static")
    app.router.add_static("/static", static_dir)

    return app


def setup_audio_capture(loop, broadcast_manager: BroadcastManager, device=None):
    broadcast_queue: asyncio.Queue = asyncio.Queue(maxsize=100)

    def audio_callback(indata, frames, time, status):
        if status:
            logger.warning("sounddevice status: %s", status)
        data = indata.astype("int16").tobytes()
        loop.call_soon_threadsafe(broadcast_queue.put_nowait, data)

    stream = sounddevice.InputStream(
        samplerate=48000,
        channels=1,
        dtype="int16",
        blocksize=960,
        callback=audio_callback,
        device=device,
    )

    async def distributor():
        while True:
            data = await broadcast_queue.get()
            await broadcast_manager.distribute(data)

    task = loop.create_task(distributor())
    return stream, task


async def main():
    args = parse_args()
    logging.basicConfig(level=logging.INFO)

    broadcast_manager = BroadcastManager()
    loop = asyncio.get_event_loop()

    stream, distributor_task = setup_audio_capture(loop, broadcast_manager, device=args.device)

    app = create_app(broadcast_manager)

    print(f"Rhemacast server starting on http://{args.host}:{args.port}")

    runner = aiohttp.web.AppRunner(app)
    await runner.setup()
    site = aiohttp.web.TCPSite(runner, args.host, args.port)

    with stream:
        await site.start()
        try:
            await asyncio.Event().wait()
        except (KeyboardInterrupt, asyncio.CancelledError):
            pass
        finally:
            distributor_task.cancel()
            await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(main())

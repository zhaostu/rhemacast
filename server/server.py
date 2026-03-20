import argparse
import asyncio
import logging

import aiohttp.web

from broadcast import BroadcastManager
from signaling import ws_handler
from web_ui import (
    index_handler,
    ws_ui_handler,
    admin_clients_handler,
    admin_kick_handler,
    admin_volume_handler,
    admin_mute_handler,
)

logger = logging.getLogger(__name__)


def parse_args(argv=None):
    parser = argparse.ArgumentParser(description="Rhemacast server")
    parser.add_argument("--device", type=int, default=None,
                        help="sounddevice device index (default: system default)")
    parser.add_argument("--host", default="0.0.0.0",
                        help="host to bind (default: 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8080,
                        help="port to bind (default: 8080)")
    parser.add_argument("--echo-cancel", action="store_true", default=False,
                        help="enable speexdsp acoustic echo cancellation")
    parser.add_argument("--admin-pin", default=None,
                        help="PIN required for /admin/* endpoints (omit to disable auth)")
    return parser.parse_args(argv)


def create_app(broadcast_manager=None, admin_pin=None) -> aiohttp.web.Application:
    if broadcast_manager is None:
        broadcast_manager = BroadcastManager()

    @aiohttp.web.middleware
    async def admin_auth_middleware(request, handler):
        if request.path.startswith("/admin/"):
            pin = request.app.get("admin_pin")
            if pin and request.headers.get("X-Admin-PIN", "") != pin:
                raise aiohttp.web.HTTPUnauthorized(reason="Invalid PIN")
        return await handler(request)

    app = aiohttp.web.Application(middlewares=[admin_auth_middleware])
    app["broadcast_manager"] = broadcast_manager
    app["client_registry"] = {}
    app["admin_pin"] = admin_pin

    async def ws_handler_wrapper(request):
        return await ws_handler(request)

    async def ws_ui_handler_wrapper(request):
        return await ws_ui_handler(request)

    app.router.add_get("/", index_handler)
    app.router.add_get("/ws", ws_handler_wrapper)
    app.router.add_get("/ws-ui", ws_ui_handler_wrapper)
    app.router.add_get("/admin/clients", admin_clients_handler)
    app.router.add_post("/admin/kick/{peer_id}", admin_kick_handler)
    app.router.add_post("/admin/volume", admin_volume_handler)
    app.router.add_post("/admin/mute", admin_mute_handler)

    import os
    static_dir = os.path.join(os.path.dirname(__file__), "static")
    app.router.add_static("/static", static_dir)

    return app


def setup_audio_capture(loop, broadcast_manager: BroadcastManager, device=None, echo_cancel=False):
    import sounddevice
    broadcast_queue: asyncio.Queue = asyncio.Queue(maxsize=100)

    ec = None
    preprocessor = None
    if echo_cancel:
        from speexdsp import EchoCanceller, Preprocessor
        ec = EchoCanceller.create(960, 9600, 48000)  # 200ms filter tail
        preprocessor = Preprocessor.create(960, 48000)
        preprocessor.ctl(0, True)   # PREPROCESS_SET_DENOISE
        preprocessor.ctl(5, True)   # PREPROCESS_SET_DEREVERB
        logger.info("Echo cancellation enabled (speexdsp)")

    def audio_callback(indata, frames, time, status):
        if status:
            logger.warning("sounddevice status: %s", status)
        data = indata.astype("int16").tobytes()
        if ec is not None and len(data) == 1920:
            ref = broadcast_manager._recent_frames[-1] if broadcast_manager._recent_frames else b'\x00' * 1920
            ec.playback(ref)
            data = ec.cancel(data)
            data = preprocessor.run(data)
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

    stream, distributor_task = setup_audio_capture(
        loop, broadcast_manager, device=args.device, echo_cancel=args.echo_cancel
    )

    app = create_app(broadcast_manager, admin_pin=args.admin_pin)

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

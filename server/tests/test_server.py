import sys
import os

sys.path.insert(0, os.path.dirname(os.path.dirname(__file__)))

from server import parse_args, create_app
from broadcast import BroadcastManager


def test_parse_args_defaults():
    args = parse_args([])
    assert args.host == "0.0.0.0"
    assert args.port == 8080
    assert args.device is None


def test_parse_args_overrides():
    args = parse_args(["--port", "9000", "--host", "127.0.0.1", "--device", "2"])
    assert args.host == "127.0.0.1"
    assert args.port == 9000
    assert args.device == 2


def test_app_routes():
    app = create_app()
    paths = [resource.canonical for resource in app.router.resources()]
    assert "/" in paths
    assert "/ws" in paths
    assert "/ws-ui" in paths


def test_app_broadcast_manager():
    app = create_app()
    assert isinstance(app["broadcast_manager"], BroadcastManager)

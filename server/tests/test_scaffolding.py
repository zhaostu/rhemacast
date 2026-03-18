"""Tests for Task 1: Scaffolding — verify required files and directories exist."""
import os

# Base path of the project (two levels up from server/tests/)
BASE = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SERVER = os.path.join(BASE, "server")


def test_server_py_exists():
    assert os.path.isfile(os.path.join(SERVER, "server.py"))


def test_audio_track_py_exists():
    assert os.path.isfile(os.path.join(SERVER, "audio_track.py"))


def test_broadcast_py_exists():
    assert os.path.isfile(os.path.join(SERVER, "broadcast.py"))


def test_signaling_py_exists():
    assert os.path.isfile(os.path.join(SERVER, "signaling.py"))


def test_web_ui_py_exists():
    assert os.path.isfile(os.path.join(SERVER, "web_ui.py"))


def test_static_index_html_exists():
    assert os.path.isfile(os.path.join(SERVER, "static", "index.html"))


def test_requirements_contains_aiortc():
    req_path = os.path.join(SERVER, "requirements.txt")
    content = open(req_path).read()
    assert "aiortc==1.14.0" in content


def test_requirements_contains_aiohttp():
    req_path = os.path.join(SERVER, "requirements.txt")
    content = open(req_path).read()
    assert "aiohttp==3.13.3" in content


def test_mobile_rhemacast_dir_exists():
    assert os.path.isdir(os.path.join(BASE, "mobile", "rhemacast"))


def test_browser_client_html_exists():
    assert os.path.isfile(os.path.join(BASE, "test", "browser_client.html"))

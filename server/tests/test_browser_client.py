"""Tests for test/browser_client.html."""
import os
from html.parser import HTMLParser
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent.parent
HTML_PATH = REPO_ROOT / "test" / "browser_client.html"


class _ErrorTrackingParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.errors = []

    def error(self, message):  # pragma: no cover
        self.errors.append(message)


def _read_html() -> str:
    return HTML_PATH.read_text(encoding="utf-8")


def test_file_exists():
    assert HTML_PATH.exists(), f"Expected {HTML_PATH} to exist"


def test_html_is_parseable():
    content = _read_html()
    parser = _ErrorTrackingParser()
    # HTMLParser.feed() does not raise on well-formed HTML; errors would appear in
    # parser.errors (only populated if the subclass error() is called).
    parser.feed(content)
    assert not parser.errors, f"HTML parse errors: {parser.errors}"


def test_contains_rtcpeerconnection():
    assert "RTCPeerConnection" in _read_html()


def test_contains_websocket():
    assert "WebSocket" in _read_html()


def test_contains_addtransceiver():
    assert "addTransceiver" in _read_html()


def test_contains_recvonly():
    assert "recvonly" in _read_html()


def test_contains_audio_element():
    assert "<audio" in _read_html()


def test_contains_server_url():
    assert "192.168.4.1:8080/ws" in _read_html()

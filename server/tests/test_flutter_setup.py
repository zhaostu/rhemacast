"""Tests for Flutter project setup (Task 7)."""
import os

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
MOBILE_ROOT = os.path.join(REPO_ROOT, 'mobile', 'rhemacast')


def _read(path):
    with open(path, 'r') as f:
        return f.read()


def test_pubspec_has_flutter_webrtc():
    content = _read(os.path.join(MOBILE_ROOT, 'pubspec.yaml'))
    assert 'flutter_webrtc' in content


def test_pubspec_has_web_socket_channel():
    content = _read(os.path.join(MOBILE_ROOT, 'pubspec.yaml'))
    assert 'web_socket_channel' in content


def test_pubspec_has_audio_session():
    content = _read(os.path.join(MOBILE_ROOT, 'pubspec.yaml'))
    assert 'audio_session' in content


def test_pubspec_has_provider():
    content = _read(os.path.join(MOBILE_ROOT, 'pubspec.yaml'))
    assert 'provider' in content


def test_android_manifest_has_internet_permission():
    content = _read(os.path.join(MOBILE_ROOT, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'))
    assert 'android.permission.INTERNET' in content


def test_android_manifest_has_cleartext_traffic():
    content = _read(os.path.join(MOBILE_ROOT, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'))
    assert 'usesCleartextTraffic' in content


def test_android_manifest_has_record_audio():
    content = _read(os.path.join(MOBILE_ROOT, 'android', 'app', 'src', 'main', 'AndroidManifest.xml'))
    assert 'android.permission.RECORD_AUDIO' in content


def test_info_plist_has_microphone_usage():
    content = _read(os.path.join(MOBILE_ROOT, 'ios', 'Runner', 'Info.plist'))
    assert 'NSMicrophoneUsageDescription' in content


def test_info_plist_has_bluetooth_usage():
    content = _read(os.path.join(MOBILE_ROOT, 'ios', 'Runner', 'Info.plist'))
    assert 'NSBluetoothAlwaysUsageDescription' in content


def test_stub_files_exist():
    stubs = [
        os.path.join(MOBILE_ROOT, 'lib', 'webrtc_client.dart'),
        os.path.join(MOBILE_ROOT, 'lib', 'audio_route.dart'),
        os.path.join(MOBILE_ROOT, 'lib', 'ui', 'home_screen.dart'),
        os.path.join(MOBILE_ROOT, 'lib', 'ui', 'status_widget.dart'),
    ]
    for path in stubs:
        assert os.path.exists(path), f"Missing stub: {path}"

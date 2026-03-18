"""Tests for App Store preparation artifacts."""
import os
import re

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
MOBILE_ROOT = os.path.join(REPO_ROOT, 'mobile', 'rhemacast')


def test_pubspec_version():
    """pubspec.yaml version should be 1.0.0+1."""
    pubspec = os.path.join(MOBILE_ROOT, 'pubspec.yaml')
    content = open(pubspec).read()
    assert re.search(r'^version:\s*1\.0\.0\+1\s*$', content, re.MULTILINE), (
        "pubspec.yaml version must be '1.0.0+1'"
    )


def test_pubspec_description_contains_translation():
    """pubspec.yaml description should mention 'translation'."""
    pubspec = os.path.join(MOBILE_ROOT, 'pubspec.yaml')
    content = open(pubspec).read()
    assert 'translation' in content.lower(), (
        "pubspec.yaml description must contain 'translation'"
    )


def test_info_plist_ui_background_modes_audio():
    """Info.plist should declare UIBackgroundModes with 'audio'."""
    info_plist = os.path.join(MOBILE_ROOT, 'ios', 'Runner', 'Info.plist')
    content = open(info_plist).read()
    assert 'UIBackgroundModes' in content, "Info.plist must contain UIBackgroundModes"
    # Ensure 'audio' appears after UIBackgroundModes key
    idx_bg = content.index('UIBackgroundModes')
    assert 'audio' in content[idx_bg:idx_bg + 200], (
        "Info.plist UIBackgroundModes must include 'audio'"
    )


def test_info_plist_microphone_usage_description():
    """Info.plist should contain NSMicrophoneUsageDescription."""
    info_plist = os.path.join(MOBILE_ROOT, 'ios', 'Runner', 'Info.plist')
    content = open(info_plist).read()
    assert 'NSMicrophoneUsageDescription' in content, (
        "Info.plist must contain NSMicrophoneUsageDescription"
    )


def test_privacy_info_xcprivacy_exists():
    """PrivacyInfo.xcprivacy must exist for iOS 17+ Privacy Manifest."""
    privacy_info = os.path.join(MOBILE_ROOT, 'ios', 'Runner', 'PrivacyInfo.xcprivacy')
    assert os.path.isfile(privacy_info), (
        f"PrivacyInfo.xcprivacy not found at {privacy_info}"
    )


def test_key_properties_template_exists():
    """key.properties.template must exist to document Android signing fields."""
    template = os.path.join(MOBILE_ROOT, 'android', 'key.properties.template')
    assert os.path.isfile(template), (
        f"key.properties.template not found at {template}"
    )

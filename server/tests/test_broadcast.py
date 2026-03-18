import asyncio
import math
import struct
from unittest.mock import patch

import numpy as np
import pytest
import pytest_asyncio

import sys
import os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

from broadcast import BroadcastManager


def make_audio_bytes(value: int, n_samples: int = 960) -> bytes:
    """Create n_samples of int16 PCM audio at a constant value."""
    return struct.pack(f"<{n_samples}h", *([value] * n_samples))


# ---------- peer registration ----------

def test_add_peer():
    bm = BroadcastManager()
    q1 = asyncio.Queue()
    q2 = asyncio.Queue()
    bm.add_peer("a", q1)
    bm.add_peer("b", q2)
    assert len(bm._peers) == 2


def test_remove_peer():
    bm = BroadcastManager()
    q1 = asyncio.Queue()
    q2 = asyncio.Queue()
    bm.add_peer("a", q1)
    bm.add_peer("b", q2)
    bm.remove_peer("a")
    assert len(bm._peers) == 1
    assert "b" in bm._peers


def test_remove_nonexistent_peer():
    bm = BroadcastManager()
    bm.remove_peer("nonexistent")  # must not raise


# ---------- distribute ----------

@pytest.mark.asyncio
async def test_distribute_fan_out():
    bm = BroadcastManager()
    q1: asyncio.Queue = asyncio.Queue()
    q2: asyncio.Queue = asyncio.Queue()
    bm.add_peer("a", q1)
    bm.add_peer("b", q2)

    data = make_audio_bytes(100)
    await bm.distribute(data)

    assert q1.get_nowait() == data
    assert q2.get_nowait() == data


@pytest.mark.asyncio
async def test_distribute_no_peers():
    bm = BroadcastManager()
    # Must not raise
    await bm.distribute(make_audio_bytes(0))


@pytest.mark.asyncio
async def test_distribute_queue_full_silently_ignored():
    bm = BroadcastManager()
    q = asyncio.Queue(maxsize=1)
    bm.add_peer("slow", q)

    data1 = make_audio_bytes(1)
    data2 = make_audio_bytes(2)

    await bm.distribute(data1)  # fills the queue
    # Queue is now full — must not raise
    await bm.distribute(data2)

    # First item should still be in queue
    assert q.get_nowait() == data1


# ---------- streaming flag ----------

@pytest.mark.asyncio
async def test_streaming_starts_false():
    bm = BroadcastManager()
    assert bm.streaming is False


@pytest.mark.asyncio
async def test_streaming_becomes_true_after_distribute():
    bm = BroadcastManager()
    assert bm.streaming is False
    await bm.distribute(make_audio_bytes(1))
    assert bm.streaming is True


# ---------- VU meter ----------

def test_get_vu_db_no_frames():
    bm = BroadcastManager()
    assert bm.get_vu_db() == -96.0


@pytest.mark.asyncio
async def test_get_vu_db_silence():
    bm = BroadcastManager()
    await bm.distribute(make_audio_bytes(0))
    assert bm.get_vu_db() == -96.0


@pytest.mark.asyncio
async def test_get_vu_db_max_amplitude():
    bm = BroadcastManager()
    # All samples at max int16 value
    await bm.distribute(make_audio_bytes(32767))
    db = bm.get_vu_db()
    # Should be very close to 0 dBFS
    assert db > -1.0, f"Expected near 0 dBFS, got {db}"
    assert db <= 0.1, f"Expected near 0 dBFS, got {db}"


# ---------- warning logging ----------

@pytest.mark.asyncio
async def test_distribute_full_queue_logs_warning():
    """When a peer's queue is full, distribute should log a warning."""
    bm = BroadcastManager()
    q = asyncio.Queue(maxsize=1)
    bm.add_peer("slow", q)

    data1 = make_audio_bytes(1)
    data2 = make_audio_bytes(2)

    await bm.distribute(data1)  # fills the queue

    with patch("broadcast.logger") as mock_logger:
        await bm.distribute(data2)  # queue full — should trigger warning
        mock_logger.warning.assert_called()

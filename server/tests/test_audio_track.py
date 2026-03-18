import asyncio
import fractions

import av
import numpy as np
import pytest

from audio_track import MicrophoneAudioTrack


def make_audio_bytes(value=1000, n=960):
    return np.full(n, value, dtype=np.int16).tobytes()


@pytest.mark.asyncio
async def test_kind():
    q = asyncio.Queue()
    track = MicrophoneAudioTrack(q)
    assert track.kind == "audio"


@pytest.mark.asyncio
async def test_first_recv_pts_and_metadata():
    q = asyncio.Queue()
    track = MicrophoneAudioTrack(q)
    await q.put(make_audio_bytes())
    frame = await track.recv()
    assert frame.pts == 0
    assert frame.sample_rate == 48000
    assert frame.time_base == fractions.Fraction(1, 48000)
    assert frame.format.name == 's16'


@pytest.mark.asyncio
async def test_pts_increments():
    q = asyncio.Queue()
    track = MicrophoneAudioTrack(q)
    await q.put(make_audio_bytes())
    await q.put(make_audio_bytes())
    frame1 = await track.recv()
    frame2 = await track.recv()
    assert frame1.pts == 0
    assert frame2.pts == 960


@pytest.mark.asyncio
async def test_frame_shape():
    q = asyncio.Queue()
    track = MicrophoneAudioTrack(q)
    await q.put(make_audio_bytes())
    frame = await track.recv()
    assert frame.to_ndarray().shape == (1, 960)


@pytest.mark.asyncio
async def test_recv_blocks_until_data():
    q = asyncio.Queue()
    track = MicrophoneAudioTrack(q)

    async def put_after_delay():
        await asyncio.sleep(0.05)
        await q.put(make_audio_bytes())

    task = asyncio.create_task(put_after_delay())
    frame = await track.recv()
    await task
    assert frame.pts == 0

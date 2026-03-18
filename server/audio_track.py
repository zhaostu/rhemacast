import asyncio
import fractions

import av
import numpy as np
from aiortc.mediastreams import AudioStreamTrack


class MicrophoneAudioTrack(AudioStreamTrack):
    kind = "audio"

    def __init__(self, queue: asyncio.Queue):
        super().__init__()
        self._queue = queue
        self._pts = 0
        self._sample_rate = 48000
        self._samples_per_frame = 960

    async def recv(self) -> av.AudioFrame:
        data = await self._queue.get()
        array = np.frombuffer(data, dtype=np.int16).reshape(1, 960)
        frame = av.AudioFrame.from_ndarray(array, format='s16', layout='mono')
        frame.sample_rate = 48000
        frame.pts = self._pts
        frame.time_base = fractions.Fraction(1, 48000)
        self._pts += 960
        return frame

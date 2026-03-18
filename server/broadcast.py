import asyncio
import collections
import logging
import math

import numpy as np

logger = logging.getLogger(__name__)


class BroadcastManager:
    def __init__(self):
        self._peers: dict[str, asyncio.Queue] = {}
        self._recent_frames: collections.deque = collections.deque(maxlen=50)
        self.streaming: bool = False

    def add_peer(self, peer_id: str, queue: asyncio.Queue) -> None:
        self._peers[peer_id] = queue

    def remove_peer(self, peer_id: str) -> None:
        self._peers.pop(peer_id, None)

    async def distribute(self, data: bytes) -> None:
        for peer_id, queue in list(self._peers.items()):
            try:
                queue.put_nowait(data)
            except asyncio.QueueFull:
                logger.warning("Queue full for peer %s — frame dropped", peer_id)

        self._recent_frames.append(data)

        if data:
            self.streaming = True

    def get_vu_db(self) -> float:
        if not self._recent_frames:
            return -96.0

        all_bytes = b"".join(self._recent_frames)
        if not all_bytes:
            return -96.0

        samples = np.frombuffer(all_bytes, dtype=np.int16).astype(np.float32)
        rms = math.sqrt(float(np.mean(samples ** 2)))

        if rms < 1.0:
            return -96.0

        return 20.0 * math.log10(rms / 32768.0)

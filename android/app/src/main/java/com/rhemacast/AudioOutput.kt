package com.rhemacast

import android.media.AudioManager

/**
 * Output routing for the listener. Policy: never auto-select the
 * loudspeaker — Auto resolves to Headphones (phone/wired/Bluetooth
 * via system priority). Loudspeaker stays as an explicit user choice.
 */
enum class AudioOutput(val label: String) {
    AUTO("Auto"),
    HEADPHONES("Headphones"),
    SPEAKER("Loudspeaker"),
}

object AudioRouter {
    @Volatile var selected: AudioOutput = AudioOutput.AUTO

    fun available(@Suppress("UNUSED_PARAMETER") m: AudioManager): List<AudioOutput> =
        listOf(AudioOutput.AUTO, AudioOutput.HEADPHONES, AudioOutput.SPEAKER)

    /** Resolve AUTO to a real device; never resolves to loudspeaker. */
    fun effective(
        requested: AudioOutput,
        @Suppress("UNUSED_PARAMETER") m: AudioManager,
    ): AudioOutput {
        if (requested != AudioOutput.AUTO) return requested
        return AudioOutput.HEADPHONES
    }

    /** Apply routing; returns the effective device. Call on connect + on selection change. */
    fun apply(m: AudioManager, requested: AudioOutput = selected): AudioOutput {
        val e = effective(requested, m)
        m.mode = AudioManager.MODE_IN_COMMUNICATION
        m.isSpeakerphoneOn = (e == AudioOutput.SPEAKER)
        try {
            if (e == AudioOutput.HEADPHONES) {
                m.startBluetoothSco()
                m.isBluetoothScoOn = true
            } else {
                m.isBluetoothScoOn = false
                try {
                    m.stopBluetoothSco()
                } catch (_: Exception) {
                }
            }
        } catch (_: Exception) {
        }
        return e
    }

    fun restore(m: AudioManager) {
        try {
            m.isBluetoothScoOn = false
            m.stopBluetoothSco()
        } catch (_: Exception) {
        }
        m.isSpeakerphoneOn = false
        m.mode = AudioManager.MODE_NORMAL
    }
}

package com.linkguard.app.engine

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioTrack
import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import kotlin.math.sin

class AlarmPlayer {

    @Volatile private var audioTrack: AudioTrack? = null
    @Volatile private var isPlaying = false
    @Volatile private var renderThread: Thread? = null
    private var vibrator: Vibrator? = null

    fun playAlarm(context: Context) {
        play(context, Mode.EVACUATION)
    }

    fun playSOSAlarm(context: Context) {
        play(context, Mode.SOS)
    }

    private enum class Mode {
        EVACUATION,
        SOS,
    }

    private fun play(context: Context, mode: Mode) {
        if (isPlaying) return
        isPlaying = true

        // 啟動振動
        startVibration(context)

        val t = Thread {
            val sampleRate = 44100
            val duration = if (mode == Mode.SOS) 4.8 else 6.0
            val totalSamples = (sampleRate * duration).toInt()

            val samples = ShortArray(totalSamples)
            if (mode == Mode.SOS) {
                // SOS：救護車 wail 音
                val lowFreq = 715.0    // 對齊 iOS 頻率
                val highFreq = 956.0   // 對齊 iOS 頻率
                val cycle = 2.4
                val fadeDuration = 0.006
                for (i in 0 until totalSamples) {
                    val t = i.toDouble() / sampleRate
                    val pos = t % cycle
                    val normalized = if (pos < cycle / 2) {
                        pos / (cycle / 2)
                    } else {
                        (cycle - pos) / (cycle / 2)
                    }
                    val freq = lowFreq + (highFreq - lowFreq) * normalized

                    val s1 = sin(2.0 * Math.PI * freq * t)
                    val s2 = sin(2.0 * Math.PI * (freq * 2.0) * t) * 0.25
                    var mixed = (s1 + s2) * 0.78

                    val halfCycle = cycle / 2
                    val posInHalf = pos % halfCycle
                    if (posInHalf < fadeDuration) mixed *= (posInHalf / fadeDuration)
                    val distToHalfEnd = halfCycle - posInHalf
                    if (distToHalfEnd < fadeDuration) mixed *= (distToHalfEnd / fadeDuration)

                    samples[i] = (mixed * Short.MAX_VALUE).toInt()
                        .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                        .toShort()
                }
            } else {
                // EVACUATION / CRITICAL：ANSI Attention Signal
                val freq1 = 853.0
                val freq2 = 960.0
                val onDuration = 1.0
                val cycleDuration = 1.5
                val fadeDuration = 0.008
                for (i in 0 until totalSamples) {
                    val t = i.toDouble() / sampleRate
                    val posInCycle = t % cycleDuration
                    if (posInCycle >= onDuration) continue

                    val tone1 = if (sin(2.0 * Math.PI * freq1 * t) > 0) 0.9 else -0.9
                    val tone2 = if (sin(2.0 * Math.PI * freq2 * t) > 0) 0.9 else -0.9
                    var mixed = (tone1 + tone2) * 0.5

                    if (posInCycle < fadeDuration) mixed *= (posInCycle / fadeDuration)
                    val distToEnd = onDuration - posInCycle
                    if (distToEnd < fadeDuration) mixed *= (distToEnd / fadeDuration)

                    samples[i] = (mixed * Short.MAX_VALUE).toInt()
                        .coerceIn(Short.MIN_VALUE.toInt(), Short.MAX_VALUE.toInt())
                        .toShort()
                }
            }

            val bufferSize = totalSamples * 2
            val track = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_ALARM)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize)
                .setTransferMode(AudioTrack.MODE_STATIC)
                .build()

            track.write(samples, 0, totalSamples)
            track.setLoopPoints(0, totalSamples, -1)
            // 將軌道內部音量拉到最大
            track.setVolume(AudioTrack.getMaxVolume())
            // 可能在 render 期間 stopAlarm() 被呼叫；isPlaying 已轉 false 則不要啟動播放
            if (!isPlaying) {
                try { track.release() } catch (_: Exception) {}
                return@Thread
            }
            track.play()
            audioTrack = track
        }
        renderThread = t
        t.start()
    }

    private fun startVibration(context: Context) {
        try {
            vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                (context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager).defaultVibrator
            } else {
                @Suppress("DEPRECATION")
                context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
            }

            val pattern = longArrayOf(0, 500, 200, 500) // 等待, 振動, 等待, 振動
            val effect = VibrationEffect.createWaveform(pattern, 0) // 0 代表無限循環
            vibrator?.vibrate(effect)
        } catch (_: SecurityException) {
            // VIBRATE 權限未授予
        }
    }

    fun stopAlarm() {
        isPlaying = false
        // 中斷 render thread（若仍在合成樣本）
        renderThread?.interrupt()
        renderThread = null
        val track = audioTrack
        audioTrack = null
        try { track?.stop() } catch (_: Exception) {}
        try { track?.release() } catch (_: Exception) {}
        vibrator?.cancel()
        vibrator = null
    }

    companion object {
        val shared = AlarmPlayer()
    }
}

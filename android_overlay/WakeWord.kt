package com.towkirhs.jarcis

import android.content.Context
import org.tensorflow.lite.Interpreter
import java.nio.ByteBuffer
import java.nio.ByteOrder

/**
 * "Hey Jarvis" detector, run entirely on the phone with openWakeWord's models (github.com/dscripka/openWakeWord,
 * models under CC BY-NC-SA 4.0): audio → melspectrogram → speech embedding → hey_jarvis score.
 * Feed it [CHUNK] samples (80 ms of 16 kHz mono 16-bit audio) at a time; it returns 0 to 1.
 */
class WakeWord(context: Context) : AutoCloseable {
    private val mel = load(context, "melspectrogram").apply {
        resizeInput(0, intArrayOf(1, CONTEXT + CHUNK))
        allocateTensors()
    }
    private val embedding = load(context, "embedding_model").apply { allocateTensors() }
    private val jarvis = load(context, "hey_jarvis_v0.1").apply { allocateTensors() }

    /** The last [CONTEXT] samples of the previous chunk, so the melspectrogram frames join up. */
    private val previous = ShortArray(CONTEXT)
    private val mels = ArrayDeque<FloatArray>().apply { repeat(MEL_WINDOW) { addLast(FloatArray(32) { 1f }) } }
    private val features = ArrayDeque<FloatArray>()

    /** Forget what was heard (after a detection), so the same words do not trigger it again. */
    fun reset() {
        previous.fill(0)
        mels.clear()
        repeat(MEL_WINDOW) { mels.addLast(FloatArray(32) { 1f }) }
        features.clear()
    }

    fun score(chunk: ShortArray): Float {
        val audio = FloatArray(CONTEXT + CHUNK)
        for (i in 0 until CONTEXT) audio[i] = previous[i].toFloat()
        for (i in 0 until CHUNK) audio[CONTEXT + i] = chunk[i].toFloat()
        System.arraycopy(chunk, CHUNK - CONTEXT, previous, 0, CONTEXT)

        val melOut = Array(1) { Array(1) { Array(8) { FloatArray(32) } } }
        mel.run(arrayOf(audio), melOut)
        for (frame in melOut[0][0]) mels.addLast(FloatArray(32) { frame[it] / 10f + 2f })
        while (mels.size > MEL_WINDOW) mels.removeFirst()

        val window = Array(1) { Array(MEL_WINDOW) { r -> Array(32) { c -> floatArrayOf(mels[r][c]) } } }
        val embOut = Array(1) { Array(1) { Array(1) { FloatArray(96) } } }
        embedding.run(window, embOut)
        features.addLast(embOut[0][0][0])
        while (features.size > FEATURES) features.removeFirst()
        if (features.size < FEATURES) return 0f

        val out = Array(1) { FloatArray(1) }
        jarvis.run(arrayOf(features.toTypedArray()), out)
        return out[0][0]
    }

    override fun close() {
        mel.close()
        embedding.close()
        jarvis.close()
    }

    companion object {
        const val CHUNK = 1280
        private const val CONTEXT = 480
        private const val MEL_WINDOW = 76
        private const val FEATURES = 16

        private fun load(context: Context, name: String): Interpreter {
            val bytes = context.assets.open("flutter_assets/assets/wakeword/$name.tflite").use { it.readBytes() }
            val buffer = ByteBuffer.allocateDirect(bytes.size).order(ByteOrder.nativeOrder())
            buffer.put(bytes).rewind()
            return Interpreter(buffer, Interpreter.Options().setNumThreads(1))
        }
    }
}

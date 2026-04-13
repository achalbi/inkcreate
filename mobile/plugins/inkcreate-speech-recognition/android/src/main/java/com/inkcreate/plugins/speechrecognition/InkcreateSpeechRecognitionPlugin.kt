package com.inkcreate.plugins.speechrecognition

import android.os.Build
import android.os.ParcelFileDescriptor
import android.webkit.CookieManager
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.common.audio.AudioSource
import com.google.mlkit.genai.speechrecognition.SpeechRecognition
import com.google.mlkit.genai.speechrecognition.SpeechRecognizer
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerRequest
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerResponse
import com.google.mlkit.genai.speechrecognition.speechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.speechRecognizerRequest
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.util.IllformedLocaleException
import java.util.Locale
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@CapacitorPlugin(name = "InkcreateSpeechRecognition")
class InkcreateSpeechRecognitionPlugin : Plugin() {
    private val pluginScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var activeJob: Job? = null

    @PluginMethod
    fun transcribeAudio(call: PluginCall) {
        startTranscription(call)
    }

    @PluginMethod
    fun startTranscription(call: PluginCall) {
        runTranscription(call)
    }

    @PluginMethod
    fun extractSpeech(call: PluginCall) {
        runTranscription(call)
    }

    override fun handleOnDestroy() {
        activeJob?.cancel()
        pluginScope.cancel()
        super.handleOnDestroy()
    }

    private fun runTranscription(call: PluginCall) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            call.unavailable("ML Kit GenAI speech recognition requires Android API 26 or newer.")
            return
        }

        val audioUrl = call.getString("audioUrl")?.trim()
        if (audioUrl.isNullOrEmpty()) {
            call.reject("An audioUrl is required to transcribe this voice note.")
            return
        }

        if (activeJob != null) {
            call.reject("Another speech transcription is already in progress.")
            return
        }

        activeJob = pluginScope.launch {
            try {
                val locale = resolveLocale(call.getString("locale"))
                val preferredMode = resolvePreferredMode(call.getString("preferredMode"))
                val recognizer = createSpeechRecognizer(locale, preferredMode)

                try {
                    ensureFeatureAvailable(recognizer, preferredMode)

                    val audioFile = downloadAudioToCache(audioUrl)
                    try {
                        val transcript = transcribeFile(recognizer, audioFile)
                        if (transcript.isBlank()) {
                            throw IllegalStateException("No speech was detected in this voice note.")
                        }

                        val payload = JSObject()
                        payload.put("text", transcript)
                        payload.put("locale", locale.toLanguageTag())
                        payload.put("preferredMode", preferredModeName(preferredMode))
                        call.resolve(payload)
                    } finally {
                        audioFile.delete()
                    }
                } finally {
                    try {
                        recognizer.stopRecognition()
                    } catch (_error: Exception) {
                    }

                    recognizer.close()
                }
            } catch (_error: CancellationException) {
                call.reject("Speech transcription was cancelled.")
            } catch (error: Exception) {
                call.reject(error.localizedMessage ?: "Speech transcription failed.", null, error)
            } finally {
                activeJob = null
            }
        }
    }

    private fun createSpeechRecognizer(locale: Locale, preferredMode: Int): SpeechRecognizer {
        return SpeechRecognition.getClient(
            speechRecognizerOptions {
                this.locale = locale
                this.preferredMode = preferredMode
            }
        )
    }

    private suspend fun ensureFeatureAvailable(recognizer: SpeechRecognizer, preferredMode: Int) {
        when (recognizer.checkStatus()) {
            FeatureStatus.AVAILABLE -> return
            FeatureStatus.DOWNLOADABLE,
            FeatureStatus.DOWNLOADING -> awaitFeatureDownload(recognizer)
            FeatureStatus.UNAVAILABLE -> throw IllegalStateException(unavailableMessage(preferredMode))
            else -> throw IllegalStateException("Speech recognition is unavailable on this device.")
        }

        if (recognizer.checkStatus() != FeatureStatus.AVAILABLE) {
            throw IllegalStateException(unavailableMessage(preferredMode))
        }
    }

    private suspend fun awaitFeatureDownload(recognizer: SpeechRecognizer) {
        val terminalStatus =
            recognizer.download().first { status ->
                status is DownloadStatus.DownloadCompleted || status is DownloadStatus.DownloadFailed
            }

        if (terminalStatus is DownloadStatus.DownloadFailed) {
            throw terminalStatus.e
        }
    }

    private suspend fun transcribeFile(recognizer: SpeechRecognizer, audioFile: File): String {
        val finalTranscript = StringBuilder()
        var partialTranscript = ""

        ParcelFileDescriptor.open(audioFile, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            val request =
                buildRecognitionRequest(descriptor)

            recognizer.startRecognition(request).collect { response ->
                when (response) {
                    is SpeechRecognizerResponse.PartialTextResponse -> partialTranscript = response.text.orEmpty()
                    is SpeechRecognizerResponse.FinalTextResponse -> {
                        finalTranscript.append(response.text.orEmpty())
                        partialTranscript = ""
                    }
                    is SpeechRecognizerResponse.CompletedResponse -> Unit
                    is SpeechRecognizerResponse.ErrorResponse -> throw response.e
                }
            }
        }

        val transcript = if (finalTranscript.isNotEmpty()) finalTranscript.toString() else partialTranscript
        return transcript.trim()
    }

    private fun buildRecognitionRequest(descriptor: ParcelFileDescriptor): SpeechRecognizerRequest {
        return speechRecognizerRequest {
            audioSource = AudioSource.fromPfd(descriptor)
        }
    }

    private suspend fun downloadAudioToCache(audioUrl: String): File = withContext(Dispatchers.IO) {
        val connection = (URL(audioUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = true
            connectTimeout = 15000
            readTimeout = 180000
            setRequestProperty("Accept", "audio/*,*/*;q=0.8")

            val cookies = CookieManager.getInstance().getCookie(audioUrl)
            if (!cookies.isNullOrBlank()) {
                setRequestProperty("Cookie", cookies)
            }

            val userAgent = System.getProperty("http.agent")
            if (!userAgent.isNullOrBlank()) {
                setRequestProperty("User-Agent", userAgent)
            }
        }

        try {
            val responseCode = connection.responseCode
            if (responseCode !in 200..299) {
                throw IOException("Could not download the voice note audio (HTTP $responseCode).")
            }

            val file = File.createTempFile("inkcreate-voice-note-", ".audio", context.cacheDir)
            connection.inputStream.use { input ->
                file.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
            file
        } finally {
            connection.disconnect()
        }
    }

    private fun resolveLocale(languageTag: String?): Locale {
        val normalizedTag = languageTag?.trim()
        if (normalizedTag.isNullOrEmpty()) {
            return Locale.getDefault()
        }

        return try {
            Locale.Builder().setLanguageTag(normalizedTag).build()
        } catch (_error: IllformedLocaleException) {
            Locale.getDefault()
        }
    }

    private fun resolvePreferredMode(mode: String?): Int {
        return if (mode.equals("advanced", ignoreCase = true)) {
            SpeechRecognizerOptions.Mode.MODE_ADVANCED
        } else {
            SpeechRecognizerOptions.Mode.MODE_BASIC
        }
    }

    private fun preferredModeName(preferredMode: Int): String {
        return if (preferredMode == SpeechRecognizerOptions.Mode.MODE_ADVANCED) "advanced" else "basic"
    }

    private fun unavailableMessage(preferredMode: Int): String {
        return if (preferredMode == SpeechRecognizerOptions.Mode.MODE_ADVANCED) {
            "Advanced speech recognition is unavailable on this device."
        } else {
            "Speech recognition is unavailable on this device. ML Kit basic mode is generally supported on Android 12 and newer devices."
        }
    }
}

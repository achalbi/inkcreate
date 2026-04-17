package com.inkcreate.mobile

import android.app.Activity
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.os.ParcelFileDescriptor
import android.util.Base64
import android.webkit.CookieManager
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.google.android.gms.tasks.Task
import com.google.mlkit.common.MlKitException
import com.google.mlkit.genai.common.DownloadCallback
import com.google.mlkit.genai.common.DownloadStatus
import com.google.mlkit.genai.common.FeatureStatus
import com.google.mlkit.genai.prompt.Candidate
import com.google.mlkit.genai.prompt.GenerateContentRequest
import com.google.mlkit.genai.prompt.Generation
import com.google.mlkit.genai.prompt.GenerativeModel
import com.google.mlkit.genai.prompt.ImagePart
import com.google.mlkit.genai.prompt.TextPart
import com.google.mlkit.genai.speechrecognition.SpeechRecognition
import com.google.mlkit.genai.speechrecognition.SpeechRecognizer
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerOptions
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerRequest
import com.google.mlkit.genai.speechrecognition.SpeechRecognizerResponse
import com.google.mlkit.genai.common.audio.AudioSource
import com.google.mlkit.genai.summarization.Summarization
import com.google.mlkit.genai.summarization.SummarizationRequest
import com.google.mlkit.genai.summarization.Summarizer
import com.google.mlkit.genai.summarization.SummarizerOptions
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import com.google.mlkit.vision.text.Text
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Date
import java.util.IllformedLocaleException
import java.util.Locale
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext

class MainActivity : FlutterFragmentActivity() {
    private data class PendingDocumentScan(
        val result: MethodChannel.Result,
        val title: String,
    )

    private val activityScope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private var pendingDocumentScan: PendingDocumentScan? = null
    private var progressSink: EventChannel.EventSink? = null
    private var activeSpeechJob: Job? = null
    private var activeSpeechRecognizer: SpeechRecognizer? = null

    private val documentScannerLauncher =
        registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { launcherResult ->
            val pending = pendingDocumentScan ?: return@registerForActivityResult
            pendingDocumentScan = null

            when (launcherResult.resultCode) {
                Activity.RESULT_OK -> {
                    activityScope.launch {
                        runCatching { buildDocumentScannerPayload(launcherResult.data, pending.title) }
                            .onSuccess(pending.result::success)
                            .onFailure { error ->
                                pending.result.error(
                                    errorCodeFor(error, fallback = FEATURE_UNAVAILABLE),
                                    error.localizedMessage ?: "Document scan failed.",
                                    null,
                                )
                            }
                    }
                }
                Activity.RESULT_CANCELED -> pending.result.success(mapOf("cancelled" to true))
                else -> pending.result.error(
                    FEATURE_UNAVAILABLE,
                    "Document scanner returned result code ${launcherResult.resultCode}.",
                    null,
                )
            }
        }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DOCUMENT_SCANNER_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "scanDocument" -> launchDocumentScanner(call, result)
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GENAI_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCapabilities" -> {
                    activityScope.launch {
                        result.success(buildGenAiCapabilities())
                    }
                }
                "runSummarization" -> {
                    activityScope.launch {
                        runCatching { runSummarization(call) }
                            .onSuccess(result::success)
                            .onFailure { error ->
                                result.error(
                                    errorCodeFor(error, fallback = FEATURE_UNAVAILABLE),
                                    error.localizedMessage ?: "Summarization failed.",
                                    null,
                                )
                            }
                    }
                }
                "runPrompt" -> {
                    activityScope.launch {
                        runCatching { runPrompt(call) }
                            .onSuccess(result::success)
                            .onFailure { error ->
                                result.error(
                                    errorCodeFor(error, fallback = FEATURE_UNAVAILABLE),
                                    error.localizedMessage ?: "Prompt inference failed.",
                                    null,
                                )
                            }
                    }
                }
                "startSpeechRecognition" -> {
                    if (activeSpeechJob != null) {
                        result.error(FEATURE_UNAVAILABLE, "Another speech job is already running.", null)
                        return@setMethodCallHandler
                    }

                    activeSpeechJob = activityScope.launch {
                        try {
                            result.success(runSpeechRecognition(call))
                        } catch (error: Exception) {
                            result.error(
                                errorCodeFor(error, fallback = FEATURE_UNAVAILABLE),
                                error.localizedMessage ?: "Speech recognition failed.",
                                null,
                            )
                        } finally {
                            activeSpeechJob = null
                        }
                    }
                }
                "cancelSpeechRecognition" -> {
                    activityScope.launch {
                        try {
                            activeSpeechRecognizer?.stopRecognition()
                            activeSpeechRecognizer?.close()
                            activeSpeechRecognizer = null
                            activeSpeechJob?.cancel()
                            activeSpeechJob = null
                            result.success(null)
                        } catch (error: Exception) {
                            activeSpeechRecognizer?.close()
                            activeSpeechRecognizer = null
                            activeSpeechJob?.cancel()
                            activeSpeechJob = null
                            result.error(
                                errorCodeFor(error, fallback = FEATURE_UNAVAILABLE),
                                error.localizedMessage ?: "Unable to cancel speech recognition.",
                                null,
                            )
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GENAI_PROGRESS_CHANNEL,
        ).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
                    progressSink = events
                }

                override fun onCancel(arguments: Any?) {
                    progressSink = null
                }
            },
        )
    }

    override fun onDestroy() {
        activeSpeechRecognizer?.close()
        activeSpeechJob?.cancel()
        activityScope.cancel()
        super.onDestroy()
    }

    private fun launchDocumentScanner(call: MethodCall, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error(OS_VERSION_TOO_LOW, "Document scanner requires Android API 26 or newer.", null)
            return
        }

        if (pendingDocumentScan != null) {
            result.error(FEATURE_UNAVAILABLE, "A document scan is already in progress.", null)
            return
        }

        val scanner = GmsDocumentScanning.getClient(buildScannerOptions(call))
        pendingDocumentScan = PendingDocumentScan(
            result = result,
            title = call.argument<String>("title") ?: defaultScanTitle(),
        )

        scanner.getStartScanIntent(this)
            .addOnSuccessListener { intentSender ->
                documentScannerLauncher.launch(IntentSenderRequest.Builder(intentSender).build())
            }
            .addOnFailureListener { error ->
                pendingDocumentScan = null
                result.error(
                    errorCodeFor(error, fallback = FEATURE_UNAVAILABLE),
                    error.localizedMessage ?: "Unable to start the document scanner.",
                    null,
                )
            }
    }

    private fun buildScannerOptions(call: MethodCall): GmsDocumentScannerOptions {
        val builder = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(call.argument<Boolean>("allowGalleryImport") ?: true)
            .setScannerMode(resolveScannerMode(call.argument<String>("scannerMode")))

        val pageLimit = call.argument<Int>("pageLimit") ?: 0
        if (pageLimit > 0) {
            builder.setPageLimit(pageLimit)
        }

        val formats = (call.argument<List<String>>("formats") ?: listOf("jpeg", "pdf"))
            .mapNotNull { format ->
                when (format.lowercase(Locale.US)) {
                    "jpeg" -> GmsDocumentScannerOptions.RESULT_FORMAT_JPEG
                    "pdf" -> GmsDocumentScannerOptions.RESULT_FORMAT_PDF
                    else -> null
                }
            }
            .distinct()
            .ifEmpty {
                listOf(
                    GmsDocumentScannerOptions.RESULT_FORMAT_JPEG,
                    GmsDocumentScannerOptions.RESULT_FORMAT_PDF,
                )
            }

        if (formats.size == 1) {
            builder.setResultFormats(formats.first())
        } else {
            builder.setResultFormats(formats[0], formats[1])
        }

        return builder.build()
    }

    private fun resolveScannerMode(mode: String?): Int {
        return when (mode?.lowercase(Locale.US)) {
            "base" -> GmsDocumentScannerOptions.SCANNER_MODE_BASE
            "base-with-filter" -> GmsDocumentScannerOptions.SCANNER_MODE_BASE_WITH_FILTER
            else -> GmsDocumentScannerOptions.SCANNER_MODE_FULL
        }
    }

    private suspend fun buildDocumentScannerPayload(data: Intent?, title: String): Map<String, Any?> {
        val scanResult = GmsDocumentScanningResult.fromActivityResultIntent(data)
            ?: throw NativeRouteException(FEATURE_UNAVAILABLE, "Document scanner returned no result.")

        val pages = scanResult.pages ?: emptyList()
        val pagePayloads = mutableListOf<Map<String, Any?>>()
        var previewImageDataUrl: String? = null

        for ((index, page) in pages.withIndex()) {
            val imageDataUrl = encodeUriAsDataUrl(page.imageUri, "image/jpeg")
            if (previewImageDataUrl == null) {
                previewImageDataUrl = imageDataUrl
            }
            pagePayloads += mapOf(
                "pageIndex" to index,
                "imageDataUrl" to imageDataUrl,
            )
        }

        val scannerPayload = mutableMapOf<String, Any?>(
            "title" to title,
            "pages" to pagePayloads,
            "pageCount" to (scanResult.pdf?.pageCount ?: pages.size),
        )

        if (!previewImageDataUrl.isNullOrBlank()) {
            scannerPayload["previewImageDataUrl"] = previewImageDataUrl
        }

        scanResult.pdf?.let { pdf ->
            scannerPayload["pdfDataUrl"] = encodeUriAsDataUrl(pdf.uri, "application/pdf")
        }

        val response = mutableMapOf<String, Any?>("scanner" to scannerPayload)
        buildOcrAnalysis(pages)?.let { analysis -> response["analysis"] = analysis }
        return response
    }

    private suspend fun buildOcrAnalysis(
        pages: List<GmsDocumentScanningResult.Page>,
    ): Map<String, Any?>? {
        if (pages.isEmpty()) {
            return null
        }

        val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)

        return try {
            val allBlocks = mutableListOf<Map<String, Any?>>()
            val allPageAnalyses = mutableListOf<Map<String, Any?>>()
            val fullText = StringBuilder()

            for ((pageIndex, page) in pages.withIndex()) {
                val recognizedText = recognizer.process(
                    InputImage.fromFilePath(this, page.imageUri),
                ).awaitTask()

                if (recognizedText.text.isNotBlank()) {
                    if (fullText.isNotEmpty()) {
                        fullText.append("\n\n")
                    }
                    fullText.append(recognizedText.text.trim())
                }

                val pageBlocks = recognizedText.textBlocks.map { block ->
                    val payload = block.toPayload().toMutableMap()
                    payload["pageIndex"] = pageIndex
                    payload.toMap()
                }
                allBlocks += pageBlocks
                allPageAnalyses += mapOf(
                    "pageIndex" to pageIndex,
                    "fullText" to recognizedText.text,
                    "blocks" to pageBlocks,
                )
            }

            mapOf(
                "ocr" to mapOf(
                    "fullText" to fullText.toString(),
                    "blocks" to allBlocks,
                    "pages" to allPageAnalyses,
                    "engine" to "google-mlkit-text-recognition-v2",
                ),
            )
        } finally {
            recognizer.close()
        }
    }

    private suspend fun buildGenAiCapabilities(): Map<String, Any?> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return mapOf(
                ROUTE_SPEECH to unsupportedCapability(OS_VERSION_TOO_LOW),
                ROUTE_SUMMARIZATION to unsupportedCapability(OS_VERSION_TOO_LOW),
                ROUTE_PROMPT to unsupportedCapability(OS_VERSION_TOO_LOW),
            )
        }

        return mapOf(
            ROUTE_SPEECH to speechCapability(),
            ROUTE_SUMMARIZATION to summarizationCapability(),
            ROUTE_PROMPT to promptCapability(),
        )
    }

    private suspend fun speechCapability(): Map<String, Any?> {
        val recognizer = createSpeechRecognizer(Locale.getDefault(), SpeechRecognizerOptions.Mode.MODE_BASIC)
        return try {
            capabilityForStatus(recognizer.checkStatus())
        } catch (error: Exception) {
            unsupportedCapability(errorCodeFor(error, fallback = AICORE_UNAVAILABLE))
        } finally {
            recognizer.close()
        }
    }

    private suspend fun summarizationCapability(): Map<String, Any?> {
        val summarizer = buildSummarizer("article", 3, "en")
        return try {
            capabilityForStatus(awaitFuture(summarizer.checkFeatureStatus()))
        } catch (error: Exception) {
            unsupportedCapability(errorCodeFor(error, fallback = AICORE_UNAVAILABLE))
        } finally {
            summarizer.close()
        }
    }

    private suspend fun promptCapability(): Map<String, Any?> {
        val model = Generation.getClient()
        return try {
            capabilityForStatus(model.checkStatus())
        } catch (error: Exception) {
            unsupportedCapability(errorCodeFor(error, fallback = AICORE_UNAVAILABLE))
        } finally {
            model.close()
        }
    }

    private suspend fun runSpeechRecognition(call: MethodCall): Map<String, Any?> {
        val requestId = call.argument<String>("requestId") ?: "speech_${System.currentTimeMillis()}"
        val audioUrl = call.argument<String>("audioUrl")?.trim()
            ?: throw NativeRouteException(FEATURE_UNAVAILABLE, "An audioUrl is required.")
        val locale = resolveLocale(call.argument<String>("locale"))
        val preferredMode = resolveSpeechMode(call.argument<String>("preferredMode"))
        val recognizer = createSpeechRecognizer(locale, preferredMode)
        activeSpeechRecognizer = recognizer

        try {
            ensureSpeechFeatureAvailable(
                recognizer = recognizer,
                requestId = requestId,
                route = ROUTE_SPEECH,
                preferredMode = preferredMode,
            )

            emitProgress(
                requestId = requestId,
                route = ROUTE_SPEECH,
                status = "processing",
                progress = 0.0,
                partialData = emptyMap(),
            )

            val audioFile = downloadAudioToCache(audioUrl)
            try {
                val transcript = transcribeFile(recognizer, audioFile, requestId)
                return mapOf(
                    "text" to transcript,
                    "locale" to locale.toLanguageTag(),
                    "preferredMode" to preferredModeName(preferredMode),
                )
            } finally {
                audioFile.delete()
            }
        } finally {
            recognizer.stopRecognition()
            recognizer.close()
            activeSpeechRecognizer = null
        }
    }

    private suspend fun ensureSpeechFeatureAvailable(
        recognizer: SpeechRecognizer,
        requestId: String,
        route: String,
        preferredMode: Int,
    ) {
        when (recognizer.checkStatus()) {
            FeatureStatus.AVAILABLE -> return
            FeatureStatus.DOWNLOADABLE,
            FeatureStatus.DOWNLOADING -> awaitDownloadFlow(
                requestId = requestId,
                route = route,
                downloadFlow = recognizer.download(),
            )
            else -> throw NativeRouteException(
                DEVICE_NOT_SUPPORTED,
                if (preferredMode == SpeechRecognizerOptions.Mode.MODE_ADVANCED) {
                    "Advanced speech recognition is unavailable on this device."
                } else {
                    "Speech recognition is unavailable on this device."
                },
            )
        }

        if (recognizer.checkStatus() != FeatureStatus.AVAILABLE) {
            throw NativeRouteException(DEVICE_NOT_SUPPORTED, "Speech recognition is unavailable on this device.")
        }
    }

    private suspend fun transcribeFile(
        recognizer: SpeechRecognizer,
        audioFile: File,
        requestId: String,
    ): String {
        val finalTranscript = StringBuilder()
        var partialTranscript = ""

        ParcelFileDescriptor.open(audioFile, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            val request = SpeechRecognizerRequest.Builder()
                .apply { audioSource = AudioSource.fromPfd(descriptor) }
                .build()

            recognizer.startRecognition(request).collect { response ->
                when (response) {
                    is SpeechRecognizerResponse.PartialTextResponse -> {
                        partialTranscript = response.text.orEmpty()
                        emitProgress(
                            requestId = requestId,
                            route = ROUTE_SPEECH,
                            status = "listening",
                            progress = null,
                            partialData = mapOf("transcript" to partialTranscript),
                        )
                    }
                    is SpeechRecognizerResponse.FinalTextResponse -> {
                        finalTranscript.append(response.text.orEmpty())
                    }
                    is SpeechRecognizerResponse.ErrorResponse -> throw response.e
                    is SpeechRecognizerResponse.CompletedResponse -> Unit
                }
            }
        }

        val transcript = if (finalTranscript.isNotEmpty()) {
            finalTranscript.toString()
        } else {
            partialTranscript
        }.trim()

        if (transcript.isBlank()) {
            throw NativeRouteException(FEATURE_UNAVAILABLE, "No speech was detected in this audio.")
        }

        return transcript
    }

    private suspend fun runSummarization(call: MethodCall): Map<String, Any?> {
        val requestId = call.argument<String>("requestId") ?: "sum_${System.currentTimeMillis()}"
        val text = call.argument<String>("text")?.trim()
            ?: throw NativeRouteException(FEATURE_UNAVAILABLE, "Text is required for summarization.")
        val mode = call.argument<String>("mode") ?: "article"
        val bulletCount = call.argument<Int>("bulletCount") ?: 3
        val language = call.argument<String>("language") ?: "en"

        val summarizer = buildSummarizer(mode, bulletCount, language)
        return try {
            ensureSummarizerReady(summarizer, requestId)
            val result = awaitFuture(
                summarizer.runInference(
                    SummarizationRequest.builder(text).build(),
                ),
            )
            val summaryText = result.summary
            mapOf(
                "summary" to summaryText,
                "bullets" to extractBullets(summaryText),
                "inputType" to mode.lowercase(Locale.US),
                "language" to language.lowercase(Locale.US),
            )
        } finally {
            summarizer.close()
        }
    }

    private fun buildSummarizer(
        mode: String,
        bulletCount: Int,
        languageCode: String,
    ): Summarizer {
        val inputType = if (mode.equals("conversation", ignoreCase = true)) {
            SummarizerOptions.InputType.CONVERSATION
        } else {
            SummarizerOptions.InputType.ARTICLE
        }
        val outputType = when (bulletCount) {
            1 -> SummarizerOptions.OutputType.ONE_BULLET
            2 -> SummarizerOptions.OutputType.TWO_BULLETS
            else -> SummarizerOptions.OutputType.THREE_BULLETS
        }
        val language = when (languageCode.lowercase(Locale.US)) {
            "ja",
            "ja-jp" -> SummarizerOptions.Language.JAPANESE
            "ko",
            "ko-kr" -> SummarizerOptions.Language.KOREAN
            else -> SummarizerOptions.Language.ENGLISH
        }

        val options = SummarizerOptions.builder(applicationContext)
            .setInputType(inputType)
            .setOutputType(outputType)
            .setLanguage(language)
            .setLongInputAutoTruncationEnabled(true)
            .build()

        return Summarization.getClient(options)
    }

    private suspend fun ensureSummarizerReady(
        summarizer: Summarizer,
        requestId: String,
    ) {
        when (awaitFuture(summarizer.checkFeatureStatus())) {
            FeatureStatus.AVAILABLE -> return
            FeatureStatus.DOWNLOADABLE,
            FeatureStatus.DOWNLOADING -> downloadSummarizerFeature(summarizer, requestId)
            else -> throw NativeRouteException(DEVICE_NOT_SUPPORTED, "Summarization is unavailable on this device.")
        }
    }

    private suspend fun downloadSummarizerFeature(
        summarizer: Summarizer,
        requestId: String,
    ) {
        suspendCancellableCoroutine<Unit> { continuation ->
            var totalBytes = 0L
            summarizer.downloadFeature(
                object : DownloadCallback {
                    override fun onDownloadStarted(bytesToDownload: Long) {
                        totalBytes = bytesToDownload
                        emitProgress(
                            requestId = requestId,
                            route = ROUTE_SUMMARIZATION,
                            status = "downloading",
                            progress = 0.0,
                            partialData = mapOf("bytesToDownload" to bytesToDownload),
                        )
                    }

                    override fun onDownloadProgress(totalBytesDownloaded: Long) {
                        val progress = if (totalBytes > 0) {
                            totalBytesDownloaded.toDouble() / totalBytes.toDouble()
                        } else {
                            null
                        }
                        emitProgress(
                            requestId = requestId,
                            route = ROUTE_SUMMARIZATION,
                            status = "downloading",
                            progress = progress,
                            partialData = mapOf(
                                "bytesDownloaded" to totalBytesDownloaded,
                                "bytesToDownload" to totalBytes,
                            ),
                        )
                    }

                    override fun onDownloadCompleted() {
                        emitProgress(
                            requestId = requestId,
                            route = ROUTE_SUMMARIZATION,
                            status = "downloading",
                            progress = 1.0,
                            partialData = mapOf("completed" to true),
                        )
                        continuation.resume(Unit)
                    }

                    override fun onDownloadFailed(e: com.google.mlkit.genai.common.GenAiException) {
                        continuation.resumeWithException(e)
                    }
                },
            )
        }
    }

    private suspend fun runPrompt(call: MethodCall): Map<String, Any?> {
        val requestId = call.argument<String>("requestId") ?: "prompt_${System.currentTimeMillis()}"
        val payloadPrompt = call.argument<String>("prompt")
        val useCase = call.argument<String>("useCase") ?: "custom"
        val text = call.argument<String>("text").orEmpty()
        val imageDataUrl = call.argument<String>("imageDataUrl")

        val prompt = payloadPrompt?.takeIf { it.isNotBlank() } ?: buildUseCasePrompt(useCase, text)
        if (prompt.isBlank()) {
            throw NativeRouteException(FEATURE_UNAVAILABLE, "A prompt or supported useCase payload is required.")
        }

        val model = Generation.getClient()
        return try {
            ensurePromptReady(model, requestId)

            val requestBuilder: GenerateContentRequest.Builder = if (!imageDataUrl.isNullOrBlank()) {
                GenerateContentRequest.Builder(
                    ImagePart(decodeDataUrl(imageDataUrl)),
                    TextPart(prompt),
                )
            } else {
                GenerateContentRequest.Builder(TextPart(prompt))
            }

            call.argument<Int>("candidateCount")?.let { candidateCount ->
                requestBuilder.candidateCount = candidateCount
            }
            call.argument<Int>("maxOutputTokens")?.let { maxOutputTokens ->
                requestBuilder.maxOutputTokens = maxOutputTokens
            }
            call.argument<Int>("topK")?.let { topK ->
                requestBuilder.topK = topK
            }
            call.argument<Double>("temperature")?.let { temperature ->
                requestBuilder.temperature = temperature.toFloat()
            }

            val response = model.generateContent(requestBuilder.build())
            val candidates = response.candidates.map { candidate ->
                mapOf(
                    "text" to candidate.text,
                    "finishReason" to candidate.finishReason,
                )
            }
            val primaryText = candidates.firstOrNull()?.get("text") as? String ?: ""

            mapOf(
                "useCase" to useCase,
                "text" to primaryText,
                "candidates" to candidates,
            )
        } finally {
            model.close()
        }
    }

    private suspend fun ensurePromptReady(
        model: GenerativeModel,
        requestId: String,
    ) {
        when (model.checkStatus()) {
            FeatureStatus.AVAILABLE -> return
            FeatureStatus.DOWNLOADABLE,
            FeatureStatus.DOWNLOADING -> awaitDownloadFlow(
                requestId = requestId,
                route = ROUTE_PROMPT,
                downloadFlow = model.download(),
            )
            else -> throw NativeRouteException(DEVICE_NOT_SUPPORTED, "Prompt inference is unavailable on this device.")
        }
    }

    private fun buildUseCasePrompt(useCase: String, text: String): String {
        if (text.isBlank()) {
            return ""
        }

        return when (useCase) {
            "ocr-structured-extraction" -> """
                You are processing OCR text for InkCreate.
                Return strict JSON with keys: title, categories, dates, money, urls, emails, phones, actionItems, summary.
                Use arrays for every key except title and summary.
                OCR text:
                $text
            """.trimIndent()
            "ocr-categorization" -> """
                Classify this OCR text for InkCreate.
                Return strict JSON with keys: documentType, confidence, tags, suggestedTitle.
                OCR text:
                $text
            """.trimIndent()
            else -> text
        }
    }

    private suspend fun awaitDownloadFlow(
        requestId: String,
        route: String,
        downloadFlow: Flow<DownloadStatus>,
    ) {
        emitProgress(
            requestId = requestId,
            route = route,
            status = "downloading",
            progress = 0.0,
            partialData = emptyMap(),
        )

        val terminalStatus = downloadFlow.first { status ->
            status is DownloadStatus.DownloadCompleted || status is DownloadStatus.DownloadFailed
        }

        when (terminalStatus) {
            is DownloadStatus.DownloadCompleted -> emitProgress(
                requestId = requestId,
                route = route,
                status = "downloading",
                progress = 1.0,
                partialData = mapOf("completed" to true),
            )
            is DownloadStatus.DownloadFailed -> throw terminalStatus.e
            else -> Unit
        }
    }

    private fun capabilityForStatus(status: Int): Map<String, Any?> {
        return when (status) {
            FeatureStatus.AVAILABLE,
            FeatureStatus.DOWNLOADABLE,
            FeatureStatus.DOWNLOADING -> supportedCapability()
            else -> unsupportedCapability(DEVICE_NOT_SUPPORTED)
        }
    }

    private fun supportedCapability(): Map<String, Any?> = mapOf(
        "supported" to true,
        "reason" to null,
    )

    private fun unsupportedCapability(reason: String): Map<String, Any?> = mapOf(
        "supported" to false,
        "reason" to reason,
    )

    private fun emitProgress(
        requestId: String,
        route: String,
        status: String,
        progress: Double?,
        partialData: Map<String, Any?>,
    ) {
        val sink = progressSink ?: return
        runOnUiThread {
            sink.success(
                mapOf(
                    "requestId" to requestId,
                    "route" to route,
                    "status" to status,
                    "progress" to progress,
                    "partialData" to partialData,
                ),
            )
        }
    }

    private fun errorCodeFor(error: Throwable, fallback: String): String {
        if (error is NativeRouteException) {
            return error.code
        }

        if (error is MlKitException && error.errorCode == MlKitException.UNSUPPORTED) {
            return DEVICE_NOT_SUPPORTED
        }

        val message = error.localizedMessage?.lowercase(Locale.US).orEmpty()
        return when {
            message.contains("aicore") -> AICORE_UNAVAILABLE
            message.contains("bootloader") -> BOOTLOADER_UNLOCKED
            message.contains("download") -> MODEL_DOWNLOAD_REQUIRED
            message.contains("unsupported") || message.contains("device") -> DEVICE_NOT_SUPPORTED
            else -> fallback
        }
    }

    private fun resolveLocale(languageTag: String?): Locale {
        val normalized = languageTag?.trim()
        if (normalized.isNullOrBlank()) {
            return Locale.getDefault()
        }

        return try {
            Locale.Builder().setLanguageTag(normalized).build()
        } catch (_: IllformedLocaleException) {
            Locale.getDefault()
        }
    }

    private fun resolveSpeechMode(mode: String?): Int {
        return if (mode.equals("advanced", ignoreCase = true)) {
            SpeechRecognizerOptions.Mode.MODE_ADVANCED
        } else {
            SpeechRecognizerOptions.Mode.MODE_BASIC
        }
    }

    private fun preferredModeName(preferredMode: Int): String {
        return if (preferredMode == SpeechRecognizerOptions.Mode.MODE_ADVANCED) {
            "advanced"
        } else {
            "basic"
        }
    }

    private fun createSpeechRecognizer(locale: Locale, preferredMode: Int): SpeechRecognizer {
        val options = SpeechRecognizerOptions.Builder()
            .apply {
                this.locale = locale
                this.preferredMode = preferredMode
            }
            .build()

        return SpeechRecognition.getClient(options)
    }

    private suspend fun downloadAudioToCache(audioUrl: String): File = withContext(Dispatchers.IO) {
        val connection = (URL(audioUrl).openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            instanceFollowRedirects = true
            connectTimeout = 15000
            readTimeout = 180000
            setRequestProperty("Accept", "audio/*,*/*;q=0.8")

            CookieManager.getInstance().getCookie(audioUrl)?.takeIf { it.isNotBlank() }?.let {
                setRequestProperty("Cookie", it)
            }
        }

        try {
            val responseCode = connection.responseCode
            if (responseCode !in 200..299) {
                throw IOException("Could not download the audio (HTTP $responseCode).")
            }

            val file = File.createTempFile("inkcreate-voice-note-", ".audio", cacheDir)
            connection.inputStream.use { input ->
                file.outputStream().use { output -> input.copyTo(output) }
            }
            file
        } finally {
            connection.disconnect()
        }
    }

    private fun encodeUriAsDataUrl(uri: Uri, fallbackMimeType: String): String {
        val mimeType = contentResolver.getType(uri) ?: fallbackMimeType
        val bytes = contentResolver.openInputStream(uri)?.use { stream -> stream.readBytes() }
            ?: throw NativeRouteException(FEATURE_UNAVAILABLE, "Could not read scanner output.")
        val encoded = Base64.encodeToString(bytes, Base64.NO_WRAP)
        return "data:$mimeType;base64,$encoded"
    }

    private fun decodeDataUrl(dataUrl: String): ByteArray {
        val base64 = dataUrl.substringAfter("base64,", "")
        if (base64.isBlank()) {
            throw NativeRouteException(FEATURE_UNAVAILABLE, "Invalid imageDataUrl payload.")
        }
        return Base64.decode(base64, Base64.DEFAULT)
    }

    private fun extractBullets(summary: String): List<String> {
        return summary
            .lines()
            .map { line -> line.trim().removePrefix("*").trim() }
            .filter { line -> line.isNotBlank() }
    }

    private suspend fun <T> Task<T>.awaitTask(): T = suspendCancellableCoroutine { continuation ->
        addOnSuccessListener { value -> continuation.resume(value) }
            .addOnFailureListener { error -> continuation.resumeWithException(error) }
    }

    private suspend fun <T> awaitFuture(future: com.google.common.util.concurrent.ListenableFuture<T>): T {
        return withContext(Dispatchers.IO) { future.get() }
    }

    private fun defaultScanTitle(): String {
        val formatter = SimpleDateFormat("MMM d, yyyy HH:mm:ss", Locale.US)
        return "Scan - ${formatter.format(Date())}"
    }

    private fun Text.TextBlock.toPayload(): Map<String, Any?> = mapOf(
        "text" to text,
        "boundingBox" to boundingBox?.toPayload(),
        "lines" to lines.map { line ->
            mapOf(
                "text" to line.text,
                "boundingBox" to line.boundingBox?.toPayload(),
                "elements" to line.elements.map { element ->
                    mapOf(
                        "text" to element.text,
                        "boundingBox" to element.boundingBox?.toPayload(),
                    )
                },
            )
        },
    )

    private fun Rect.toPayload(): Map<String, Int> = mapOf(
        "left" to left,
        "top" to top,
        "right" to right,
        "bottom" to bottom,
        "width" to width(),
        "height" to height(),
    )

    private class NativeRouteException(
        val code: String,
        override val message: String,
    ) : Exception(message)

    companion object {
        private const val DOCUMENT_SCANNER_CHANNEL = "com.inkcreate.mobile/document_scanner"
        private const val GENAI_CHANNEL = "com.inkcreate.mobile/genai"
        private const val GENAI_PROGRESS_CHANNEL = "com.inkcreate.mobile/genai_progress"

        private const val ROUTE_SPEECH = "genai:speech-recognition"
        private const val ROUTE_SUMMARIZATION = "genai:summarization"
        private const val ROUTE_PROMPT = "genai:prompt"

        private const val FEATURE_UNAVAILABLE = "FEATURE_UNAVAILABLE"
        private const val DEVICE_NOT_SUPPORTED = "DEVICE_NOT_SUPPORTED"
        private const val AICORE_UNAVAILABLE = "AICORE_UNAVAILABLE"
        private const val MODEL_DOWNLOAD_REQUIRED = "MODEL_DOWNLOAD_REQUIRED"
        private const val OS_VERSION_TOO_LOW = "OS_VERSION_TOO_LOW"
        private const val BOOTLOADER_UNLOCKED = "BOOTLOADER_UNLOCKED"
    }
}

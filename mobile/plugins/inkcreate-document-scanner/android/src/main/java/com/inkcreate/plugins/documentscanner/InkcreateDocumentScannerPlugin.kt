package com.inkcreate.plugins.documentscanner

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Base64
import androidx.activity.result.ActivityResultLauncher
import androidx.activity.result.IntentSenderRequest
import androidx.activity.result.contract.ActivityResultContracts
import com.getcapacitor.JSArray
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.google.mlkit.common.MlKitException
import com.google.mlkit.vision.documentscanner.GmsDocumentScannerOptions
import com.google.mlkit.vision.documentscanner.GmsDocumentScanning
import com.google.mlkit.vision.documentscanner.GmsDocumentScanningResult
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@CapacitorPlugin(name = "InkcreateDocumentScanner")
class InkcreateDocumentScannerPlugin : Plugin() {
    private var pendingCall: PluginCall? = null
    private var scannerLauncher: ActivityResultLauncher<IntentSenderRequest>? = null

    override fun load() {
        scannerLauncher =
            activity.registerForActivityResult(ActivityResultContracts.StartIntentSenderForResult()) { result ->
                val call = pendingCall
                pendingCall = null
                if (call == null) return@registerForActivityResult

                when (result.resultCode) {
                    Activity.RESULT_OK -> handleScannerSuccess(call, result.data)
                    Activity.RESULT_CANCELED -> {
                        val payload = JSObject()
                        payload.put("cancelled", true)
                        call.resolve(payload)
                    }
                    else -> call.reject("Document scanner returned result code ${result.resultCode}.")
                }
            }
    }

    @PluginMethod
    fun scanDocument(call: PluginCall) {
        launchScanner(call)
    }

    @PluginMethod
    fun startScan(call: PluginCall) {
        launchScanner(call)
    }

    @PluginMethod
    fun openScanner(call: PluginCall) {
        launchScanner(call)
    }

    private fun launchScanner(call: PluginCall) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
            call.unavailable("ML Kit document scanner requires Android API 21 or newer.")
            return
        }

        if (pendingCall != null) {
            call.reject("A document scan is already in progress.")
            return
        }

        val launcher = scannerLauncher
        if (launcher == null) {
            call.unavailable("Document scanner launcher is unavailable.")
            return
        }

        val scanner = GmsDocumentScanning.getClient(buildScannerOptions(call))
        pendingCall = call

        scanner.getStartScanIntent(activity)
            .addOnSuccessListener { intentSender ->
                launcher.launch(IntentSenderRequest.Builder(intentSender).build())
            }
            .addOnFailureListener { error ->
                pendingCall = null

                if (error is MlKitException && error.errorCode == MlKitException.UNSUPPORTED) {
                    call.unavailable("ML Kit document scanner is unsupported on this device.")
                    return@addOnFailureListener
                }

                call.reject(error.localizedMessage ?: "Unable to start the document scanner.", null, error)
            }
    }

    private fun buildScannerOptions(call: PluginCall): GmsDocumentScannerOptions {
        val builder = GmsDocumentScannerOptions.Builder()
            .setGalleryImportAllowed(call.getBoolean("allowGalleryImport", true) ?: true)
            .setScannerMode(resolveScannerMode(call.getString("scannerMode", "full")))

        val pageLimit = call.getInt("pageLimit", 0) ?: 0
        if (pageLimit > 0) builder.setPageLimit(pageLimit)

        val requestedFormats = resolveResultFormats(call.getArray("formats"))
        when (requestedFormats.size) {
            1 -> builder.setResultFormats(requestedFormats[0])
            else -> builder.setResultFormats(requestedFormats[0], requestedFormats[1])
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

    private fun resolveResultFormats(formats: JSArray?): List<Int> {
        val values = mutableListOf<Int>()

        for (index in 0 until (formats?.length() ?: 0)) {
            when (formats?.optString(index)?.lowercase(Locale.US)) {
                "jpeg" -> values.add(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
                "pdf" -> values.add(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
            }
        }

        if (values.isEmpty()) {
            values.add(GmsDocumentScannerOptions.RESULT_FORMAT_JPEG)
            values.add(GmsDocumentScannerOptions.RESULT_FORMAT_PDF)
        }

        return values.distinct()
    }

    private fun handleScannerSuccess(call: PluginCall, data: Intent?) {
        val result = GmsDocumentScanningResult.fromActivityResultIntent(data)
        if (result == null) {
            call.reject("Document scanner returned no result.")
            return
        }

        val payload = JSObject()
        payload.put("title", call.getString("title", defaultTitle()))

        val pagesArray = JSArray()
        val pages = result.pages ?: emptyList()
        var previewImageDataUrl: String? = null

        pages.forEachIndexed { index, page ->
            val imageDataUrl = uriToDataUrl(page.imageUri, "image/jpeg")
            if (previewImageDataUrl == null) previewImageDataUrl = imageDataUrl

            val pagePayload = JSObject()
            pagePayload.put("pageIndex", index)
            pagePayload.put("imageDataUrl", imageDataUrl)
            pagesArray.put(pagePayload)
        }

        payload.put("pages", pagesArray)
        payload.put("pageCount", result.pdf?.pageCount ?: pages.size)

        if (!previewImageDataUrl.isNullOrBlank()) {
            payload.put("previewImageDataUrl", previewImageDataUrl)
        }

        result.pdf?.let { pdf ->
            val pdfDataUrl = uriToDataUrl(pdf.uri, "application/pdf")
            if (!pdfDataUrl.isNullOrBlank()) {
                payload.put("pdfDataUrl", pdfDataUrl)
            }
        }

        call.resolve(payload)
    }

    private fun uriToDataUrl(uri: Uri, fallbackMimeType: String): String? {
        val resolver = context.contentResolver
        val mimeType = resolver.getType(uri) ?: fallbackMimeType
        val bytes = resolver.openInputStream(uri)?.use { stream -> stream.readBytes() } ?: return null
        val base64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
        return "data:$mimeType;base64,$base64"
    }

    private fun defaultTitle(): String {
        val formatter = SimpleDateFormat("MMM d, yyyy HH:mm:ss", Locale.US)
        return "Scan - ${formatter.format(Date())}"
    }
}

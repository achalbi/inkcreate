import AVFoundation
import Flutter
import UIKit
import VisionKit

@main
@objc class AppDelegate: FlutterAppDelegate, VNDocumentCameraViewControllerDelegate, FlutterStreamHandler {
  private let documentScannerChannelName = "com.inkcreate.mobile/document_scanner"
  private let genAiChannelName = "com.inkcreate.mobile/genai"
  private let genAiProgressChannelName = "com.inkcreate.mobile/genai_progress"

  private var documentScannerResult: FlutterResult?
  private var documentScannerTitle = "Scan"
  private var progressSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let didFinish = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      configureChannels(binaryMessenger: controller.binaryMessenger)
    }
    return didFinish
  }

  private func configureChannels(binaryMessenger: FlutterBinaryMessenger) {
    let documentScannerChannel = FlutterMethodChannel(
      name: documentScannerChannelName,
      binaryMessenger: binaryMessenger
    )
    documentScannerChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      switch call.method {
      case "scanDocument":
        self.handleDocumentScanner(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    let genAiChannel = FlutterMethodChannel(
      name: genAiChannelName,
      binaryMessenger: binaryMessenger
    )
    genAiChannel.setMethodCallHandler { [weak self] call, result in
      guard let self else { return }
      self.handleGenAi(call: call, result: result)
    }

    let progressChannel = FlutterEventChannel(
      name: genAiProgressChannelName,
      binaryMessenger: binaryMessenger
    )
    progressChannel.setStreamHandler(self)
  }

  private func handleDocumentScanner(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard #available(iOS 13.0, *), VNDocumentCameraViewController.isSupported else {
      result(
        FlutterError(
          code: "FEATURE_UNAVAILABLE",
          message: "VisionKit document scanning is unavailable on this iOS device.",
          details: nil
        )
      )
      return
    }

    guard documentScannerResult == nil else {
      result(
        FlutterError(
          code: "FEATURE_UNAVAILABLE",
          message: "Another document scan is already in progress.",
          details: nil
        )
      )
      return
    }

    if let args = call.arguments as? [String: Any],
      let title = args["title"] as? String,
      !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    {
      documentScannerTitle = title
    } else {
      documentScannerTitle = defaultScanTitle()
    }

    documentScannerResult = result

    DispatchQueue.main.async {
      let scanner = VNDocumentCameraViewController()
      scanner.delegate = self
      self.window?.rootViewController?.present(scanner, animated: true)
    }
  }

  private func handleGenAi(call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "getCapabilities":
      result([
        "genai:speech-recognition": unsupportedCapability("ANDROID_ONLY"),
        "genai:summarization": unsupportedCapability("ANDROID_ONLY"),
        "genai:prompt": unsupportedCapability("ANDROID_ONLY"),
      ])
    case "runSummarization", "runPrompt", "startSpeechRecognition":
      result(
        FlutterError(
          code: "ANDROID_ONLY",
          message: "This GenAI route is Android-only in the current InkCreate shell.",
          details: nil
        )
      )
    case "cancelSpeechRecognition":
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func supportedCapability() -> [String: Any?] {
    [
      "supported": true,
      "reason": nil,
    ]
  }

  private func unsupportedCapability(_ reason: String) -> [String: Any?] {
    [
      "supported": false,
      "reason": reason,
    ]
  }

  private func defaultScanTitle() -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d, yyyy HH:mm:ss"
    return "Scan - \(formatter.string(from: Date()))"
  }

  @available(iOS 13.0, *)
  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true)
    documentScannerResult?(["cancelled": true])
    documentScannerResult = nil
  }

  @available(iOS 13.0, *)
  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFailWithError error: Error
  ) {
    controller.dismiss(animated: true)
    documentScannerResult?(
      FlutterError(
        code: "FEATURE_UNAVAILABLE",
        message: error.localizedDescription,
        details: nil
      )
    )
    documentScannerResult = nil
  }

  @available(iOS 13.0, *)
  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController,
    didFinishWith scan: VNDocumentCameraScan
  ) {
    controller.dismiss(animated: true) {
      let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
      let payload = self.buildDocumentScannerPayload(images: pages)
      self.documentScannerResult?(payload)
      self.documentScannerResult = nil
    }
  }

  @available(iOS 13.0, *)
  private func buildDocumentScannerPayload(images: [UIImage]) -> [String: Any] {
    let pagePayloads = images.enumerated().compactMap { index, image -> [String: Any]? in
      guard let imageDataUrl = jpegDataUrl(image) else { return nil }
      return [
        "pageIndex": index,
        "imageDataUrl": imageDataUrl,
      ]
    }

    var scanner: [String: Any] = [
      "title": documentScannerTitle,
      "pages": pagePayloads,
      "pageCount": images.count,
    ]

    if let first = images.first.flatMap(jpegDataUrl(_:)) {
      scanner["previewImageDataUrl"] = first
    }

    if let pdfDataUrl = pdfDataUrl(images) {
      scanner["pdfDataUrl"] = pdfDataUrl
    }

    return [
      "scanner": scanner,
    ]
  }

  private func jpegDataUrl(_ image: UIImage) -> String? {
    guard let data = image.jpegData(compressionQuality: 0.92) else { return nil }
    return dataUrl(data, mimeType: "image/jpeg")
  }

  private func pdfDataUrl(_ images: [UIImage]) -> String? {
    guard !images.isEmpty else { return nil }
    let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
    let renderer = UIGraphicsPDFRenderer(bounds: bounds)
    let pdfData = renderer.pdfData { context in
      for image in images {
        context.beginPage()
        let fittedRect = AVMakeRect(aspectRatio: image.size, insideRect: bounds.insetBy(dx: 18, dy: 18))
        image.draw(in: fittedRect)
      }
    }
    return dataUrl(pdfData, mimeType: "application/pdf")
  }

  private func dataUrl(_ data: Data, mimeType: String) -> String {
    "data:\(mimeType);base64,\(data.base64EncodedString())"
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    progressSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    progressSink = nil
    return nil
  }
}

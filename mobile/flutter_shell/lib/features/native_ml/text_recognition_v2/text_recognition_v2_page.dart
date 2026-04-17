import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/models/native_bridge_models.dart';

class TextRecognitionV2Page extends StatefulWidget {
  const TextRecognitionV2Page({
    super.key,
    required this.requestId,
    required this.route,
    required this.payload,
  });

  final String requestId;
  final String route;
  final Map<String, dynamic> payload;

  @override
  State<TextRecognitionV2Page> createState() => _TextRecognitionV2PageState();
}

class _TextRecognitionV2PageState extends State<TextRecognitionV2Page> {
  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final ImageSource imageSource = widget.payload['source'] == 'gallery'
        ? ImageSource.gallery
        : ImageSource.camera;
    final XFile? selected = await _picker.pickImage(source: imageSource);

    if (!mounted) {
      return;
    }

    if (selected == null) {
      Navigator.of(context).pop(
        NativeRouteResult.cancelled(
          requestId: widget.requestId,
          route: widget.route,
        ),
      );
      return;
    }

    final TextRecognizer recognizer = TextRecognizer(
      script: TextRecognitionScript.latin,
    );
    final RecognizedText recognizedText = await recognizer.processImage(
      InputImage.fromFile(File(selected.path)),
    );
    await recognizer.close();

    if (!mounted) {
      return;
    }

    Navigator.of(context).pop(
      NativeRouteResult.success(
        requestId: widget.requestId,
        route: widget.route,
        data: <String, dynamic>{
          'fullText': recognizedText.text,
          'blocks': recognizedText.blocks
              .map(
                (TextBlock block) => <String, dynamic>{
                  'text': block.text,
                  'boundingBox': _rectJson(block.boundingBox),
                  'recognizedLanguages': block.recognizedLanguages,
                  'lines': block.lines
                      .map(
                        (TextLine line) => <String, dynamic>{
                          'text': line.text,
                          'boundingBox': _rectJson(line.boundingBox),
                          'recognizedLanguages': line.recognizedLanguages,
                          'elements': line.elements
                              .map(
                                (TextElement element) => <String, dynamic>{
                                  'text': element.text,
                                  'boundingBox': _rectJson(element.boundingBox),
                                  'recognizedLanguages':
                                      element.recognizedLanguages,
                                },
                              )
                              .toList(growable: false),
                        },
                      )
                      .toList(growable: false),
                },
              )
              .toList(growable: false),
        },
      ),
    );
  }

  Map<String, dynamic>? _rectJson(Rect? rect) {
    if (rect == null) {
      return null;
    }

    return <String, dynamic>{
      'left': rect.left,
      'top': rect.top,
      'right': rect.right,
      'bottom': rect.bottom,
      'width': rect.width,
      'height': rect.height,
    };
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

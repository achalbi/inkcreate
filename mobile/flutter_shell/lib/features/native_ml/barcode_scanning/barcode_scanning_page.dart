import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/models/native_bridge_models.dart';

class BarcodeScanningPage extends StatefulWidget {
  const BarcodeScanningPage({
    super.key,
    required this.requestId,
    required this.route,
  });

  final String requestId;
  final String route;

  @override
  State<BarcodeScanningPage> createState() => _BarcodeScanningPageState();
}

class _BarcodeScanningPageState extends State<BarcodeScanningPage> {
  bool _completed = false;

  void _complete(BarcodeCapture capture) {
    if (_completed || capture.barcodes.isEmpty) {
      return;
    }

    _completed = true;
    final Barcode barcode = capture.barcodes.first;

    Navigator.of(context).pop(
      NativeRouteResult.success(
        requestId: widget.requestId,
        route: widget.route,
        data: <String, dynamic>{
          'rawValue': barcode.rawValue,
          'format': barcode.format.name,
          'parsedValueType': barcode.type.name,
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(title: const Text('Scan barcode')),
      body: MobileScanner(onDetect: _complete),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class InkCreateApp extends StatelessWidget {
  const InkCreateApp({super.key, required this.router});

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'InkCreate',
      routerConfig: router,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF244C38),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF6F1E7),
        useMaterial3: true,
      ),
    );
  }
}

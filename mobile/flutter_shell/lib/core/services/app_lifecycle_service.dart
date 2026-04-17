import 'package:flutter/widgets.dart';

class AppLifecycleService extends ChangeNotifier with WidgetsBindingObserver {
  AppLifecycleService() {
    WidgetsBinding.instance.addObserver(this);
  }

  bool _isForeground = true;

  bool get isForeground => _isForeground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final bool nextForeground = state == AppLifecycleState.resumed;
    if (_isForeground == nextForeground) {
      return;
    }

    _isForeground = nextForeground;
    notifyListeners();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

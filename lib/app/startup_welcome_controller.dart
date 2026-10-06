import 'dart:async';

import 'package:flutter/foundation.dart';

/// One startup per bootstrap lifetime, independent of workspace generations.
class StartupWelcomeController extends ChangeNotifier {
  StartupWelcomeController({this.minimumDuration = const Duration(seconds: 2)});

  final Duration minimumDuration;
  final _revealed = Completer<void>();
  Timer? _timer;
  bool _started = false;
  bool _minimumElapsed = false;
  bool _ready = false;
  bool _visible = true;
  bool _disposed = false;
  String? _error;

  Future<void> get startupRevealed => _revealed.future;
  bool get visible => _visible;
  bool get waiting => _minimumElapsed && !_ready && _error == null;
  String? get error => _error;
  bool get canReveal => _minimumElapsed && _ready && _error == null;

  /// Called after the first Flutter frame, never again on retry or resume.
  void start() {
    if (_started || _disposed) return;
    _started = true;
    _timer = Timer(minimumDuration, () {
      if (_disposed) return;
      _minimumElapsed = true;
      notifyListeners();
    });
  }

  void markReady() {
    if (_disposed || !_visible) return;
    _ready = true;
    _error = null;
    notifyListeners();
  }

  void markWaiting() {
    if (_disposed || !_visible) return;
    _ready = false;
    _error = null;
    notifyListeners();
  }

  void fail(String message) {
    if (_disposed || !_visible) return;
    _ready = false;
    _error = message;
    notifyListeners();
  }

  /// The gate calls this only after its exit animation has finished.
  void reveal() {
    if (_disposed || !_visible || !canReveal) return;
    _visible = false;
    _revealed.complete();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

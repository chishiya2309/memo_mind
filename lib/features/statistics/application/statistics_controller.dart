import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/statistics_time_zone.dart';
import '../domain/statistics_models.dart';
import '../domain/statistics_repository.dart';

enum StatisticsLoadState { loading, ready, error, stale }

class StatisticsController extends ChangeNotifier {
  StatisticsController({
    required this.repository,
    required Stream<void> studyChanges,
    this.supported = true,
    DateTime Function()? clock,
    Future<String> Function()? timeZone,
  }) : _clock = clock ?? DateTime.now,
       _timeZone = timeZone ?? deviceStatisticsTimeZone {
    _subscription = studyChanges.listen((_) {
      if (_active) refresh();
    });
  }

  final StatisticsRepository repository;
  final bool supported;
  final DateTime Function() _clock;
  final Future<String> Function() _timeZone;
  late final StreamSubscription<void> _subscription;
  StatisticsSnapshot? snapshot;
  StatisticsLoadState state = StatisticsLoadState.loading;
  bool refreshing = false;
  bool _visible = false, _resumed = true, _disposed = false;
  int _request = 0;
  Timer? _boundary, _poll;
  final Stopwatch _elapsed = Stopwatch();
  DateTime? _anchor;
  bool get _active => supported && _visible && _resumed && !_disposed;

  void setVisible(bool visible) {
    if (_visible == visible || _disposed) return;
    _visible = visible;
    _updateActivity();
  }

  void setResumed(bool resumed) {
    if (_disposed) return;
    _resumed = resumed;
    _updateActivity();
  }

  void _updateActivity() {
    _cancelTimers();
    if (_active) {
      refresh();
    } else {
      _request++; // Invalidate work started before the surface was hidden.
      refreshing = false;
    }
  }

  Future<void> refresh() async {
    if (!supported || _disposed) return;
    final request = ++_request;
    refreshing = true;
    if (snapshot == null) state = StatisticsLoadState.loading;
    notifyListeners();
    try {
      final next = await repository.loadSnapshot();
      if (_disposed || request != _request) return;
      snapshot = next;
      state = StatisticsLoadState.ready;
    } catch (_) {
      if (_disposed || request != _request) return;
      state = snapshot == null
          ? StatisticsLoadState.error
          : StatisticsLoadState.stale;
    }
    if (_disposed || request != _request) return;
    refreshing = false;
    notifyListeners();
    _schedule();
  }

  void _schedule() {
    _cancelTimers();
    if (!_active) return;
    _anchor = _clock();
    _elapsed
      ..reset()
      ..start();
    final data = snapshot;
    if (data != null && state == StatisticsLoadState.ready) {
      final due = data.nextDueAt;
      final target = due != null && due.isBefore(data.nextLocalMidnight)
          ? due
          : data.nextLocalMidnight;
      final delay = target.difference(_clock());
      _boundary = Timer(delay.isNegative ? Duration.zero : delay, refresh);
    }
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _checkTime());
  }

  Future<void> _checkTime() async {
    final request = _request;
    try {
      final zone = await _timeZone();
      if (!_active || request != _request || refreshing) return;
      final now = _clock();
      final data = snapshot;
      final drift = now.difference(_anchor!) - _elapsed.elapsed;
      final local = now.toUtc();
      if (data == null ||
          data.timeZoneId != zone ||
          drift.inMilliseconds.abs() > 2000 ||
          !local.isBefore(data.nextLocalMidnight) ||
          (data.nextDueAt != null && !local.isBefore(data.nextDueAt!))) {
        await refresh();
      }
    } catch (_) {
      // A normal load reports timezone/database failures through the UI.
      if (_active && request == _request && !refreshing) await refresh();
    }
  }

  void _cancelTimers() {
    _boundary?.cancel();
    _poll?.cancel();
    _elapsed.stop();
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    _cancelTimers();
    _subscription.cancel();
    super.dispose();
  }
}

class ReminderTapRouter {
  ReminderTapRouter({
    required this.ready,
    required this.open,
    required this.refresh,
    required this.onError,
  });
  final Future<void> Function() ready, open;
  final void Function() refresh;
  final void Function(Object) onError;
  Future<void>? _opening;
  bool _visible = false;

  Future<void> handle() {
    if (_opening != null) {
      if (_visible) refresh();
      return _opening!;
    }
    final future = _handle();
    _opening = future;
    future.then((_) {
      _opening = null;
      _visible = false;
    });
    return future;
  }

  Future<void> _handle() async {
    try {
      await ready();
      _visible = true;
      await open();
    } catch (error) {
      onError(error);
    }
  }
}

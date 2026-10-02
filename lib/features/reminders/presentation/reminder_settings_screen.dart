import 'package:flutter/material.dart';

import '../application/reminder_coordinator.dart';
import '../domain/reminder_models.dart';

class ReminderSettingsScreen extends StatefulWidget {
  const ReminderSettingsScreen({super.key, required this.coordinator});
  final ReminderCoordinator coordinator;
  @override
  State<ReminderSettingsScreen> createState() => _ReminderSettingsScreenState();
}

class _ReminderSettingsScreenState extends State<ReminderSettingsScreen> {
  bool _enabled = false, _loaded = false, _saving = false;
  TimeOfDay? _time;
  String? _error;
  String? _loadError;
  ReminderCoordinator get coordinator => widget.coordinator;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!coordinator.gateway.supported) {
      await coordinator.reconcile();
      return;
    }
    try {
      final settings = await coordinator.repository.readSettings();
      await coordinator.reconcile();
      if (!mounted) return;
      setState(() {
        _enabled = settings.enabled;
        _time = settings.hour == null
            ? null
            : TimeOfDay(hour: settings.hour!, minute: settings.minute!);
        _loaded = true;
        _loadError = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadError = 'Không thể tải cài đặt nhắc học');
      }
    }
  }

  Future<void> _save() async {
    if (_enabled && _time == null) {
      setState(() => _error = 'Vui lòng chọn giờ trong khoảng 00:00–23:59.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_enabled) {
        // A failure to request permission must not discard the saved intention.
        try {
          final access = await coordinator.checkPermission();
          if (access.canRequest && mounted) {
            final consent = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Cho phép nhắc học'),
                content: const Text(
                  'MemoMind dùng thông báo để nhắc bạn ôn thẻ đến hạn '
                  'vào giờ đã chọn, kể cả khi không có mạng.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Để sau'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Tiếp tục'),
                  ),
                ],
              ),
            );
            if (consent == true) await coordinator.requestPermission();
          }
        } catch (_) {
          /* Reconcile reports permission/platform errors after saving. */
        }
      }
      if (!mounted) return;
      await coordinator.save(
        ReminderSettings(
          enabled: _enabled,
          hour: _time?.hour,
          minute: _time?.minute,
          lastKnownTimeZone: coordinator.settings.lastKnownTimeZone,
          updatedAt: coordinator.clock().toUtc(),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(coordinator.message)));
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Chưa lưu được cài đặt nhắc học');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openSettings() async {
    try {
      await coordinator.gateway.openSettings();
    } catch (_) {
      if (mounted) setState(() => _error = 'Không thể mở cài đặt thiết bị.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Nhắc học')),
    body: ListenableBuilder(
      listenable: coordinator,
      builder: (context, _) {
        if (!coordinator.gateway.supported) {
          return Center(child: Text(coordinator.message));
        }
        if (!_loaded) {
          return _loadError == null
              ? const Center(child: CircularProgressIndicator())
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_loadError!),
                      TextButton(
                        onPressed: _load,
                        child: const Text('Thử tải lại'),
                      ),
                    ],
                  ),
                );
        }
        final next = coordinator.nextReminder?.toLocal();
        final access = coordinator.permission;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Nhắc thẻ đến hạn'),
              subtitle: const Text('Một giờ nhắc mỗi ngày cho toàn bộ thẻ'),
              value: _enabled,
              onChanged: _saving ? null : (v) => setState(() => _enabled = v),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Giờ nhắc hằng ngày'),
              subtitle: Text(
                _time == null
                    ? 'Chưa chọn giờ'
                    : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: _saving
                  ? null
                  : () async {
                      final selected = await showTimePicker(
                        context: context,
                        initialTime: _time ?? TimeOfDay.now(),
                        builder: (context, child) => MediaQuery(
                          data: MediaQuery.of(context)
                              .copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        ),
                      );
                      if (selected != null && mounted) {
                        setState(() {
                          _time = selected;
                          _error = null;
                        });
                      }
                    },
            ),
            const SizedBox(height: 16),
            Text(
              access == null
                  ? 'Chưa kiểm tra được quyền thông báo'
                  : 'Quyền thông báo: ${access.appAllowed ? 'Được phép' : 'Bị chặn'}\n'
                        'Kênh nhắc học: ${access.channelAllowed ? 'Được phép' : 'Bị chặn'}',
            ),
            const SizedBox(height: 16),
            Text(coordinator.message),
            if (next != null)
              Text(
                'Lần nhắc tiếp theo: '
                '${next.day}/${next.month}/${next.year} '
                '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')}',
              ),
            if (access != null && !access.allowed)
              TextButton.icon(
                onPressed: _saving ? null : _openSettings,
                icon: const Icon(Icons.settings),
                label: const Text('Mở cài đặt thiết bị'),
              ),
            if (coordinator.status == ReminderStatus.needsReconcile)
              TextButton(
                onPressed: _saving
                    ? null
                    : () => coordinator.reconcile(force: true),
                child: const Text('Thử cập nhật lại lịch'),
              ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'Đang lưu…' : 'Lưu'),
            ),
            TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            const SizedBox(height: 16),
            const Text(
              'Lịch nhắc được làm mới khi bạn mở ứng dụng hoặc thay đổi dữ liệu học. '
              'Thông báo có thể dừng sau 7 ngày nếu bạn không mở ứng dụng. '
              'Thiết bị có thể hiển thị thông báo muộn hơn giờ đã chọn.',
            ),
          ],
        );
      },
    ),
  );
}

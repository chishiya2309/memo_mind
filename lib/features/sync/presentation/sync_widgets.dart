import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../core/workspace/workspace_context.dart';
import '../../account_backup/application/account_backup_controller.dart';
import '../../account_backup/domain/auth_repository.dart';
import '../../deck_management/data/local_deck_repository.dart';
import '../../deck_management/data/local_deck_repository_io.dart' as local_io;
import '../../deck_management/presentation/card_editor_dialog.dart';
import '../application/sync_controller.dart';

String syncDate(DateTime date) {
  final d = date.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(d.day)}/${pad(d.month)}/${d.year} ${pad(d.hour)}:${pad(d.minute)}';
}

class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({super.key, required this.controller, this.onSignIn});
  final SyncController controller;
  final VoidCallback? onSignIn;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) => Tooltip(
      message: controller.status,
      child: TextButton.icon(
        onPressed: controller.busy
            ? null
            : controller.available &&
                  !controller.requiresAuthentication &&
                  !controller.accountBlocked &&
                  !controller.needsMigration
            ? controller.syncNow
            : onSignIn,
        icon: controller.busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.sync),
        label: Text(controller.pendingChanges ? 'Chưa đồng bộ' : 'Đồng bộ'),
      ),
    ),
  );
}

class SyncAccountPanel extends StatelessWidget {
  const SyncAccountPanel({
    super.key,
    required this.controller,
    required this.run,
    required this.onReauthenticate,
    this.busy = false,
  });
  final AccountBackupController controller;
  final Future<void> Function(Future<void> Function()) run;
  final Future<void> Function() onReauthenticate;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final c = controller, sync = c.sync;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        const Text('Thư viện học của bạn'),
        if (sync.lastSynced == null)
          const Text(
            'Thư viện trên thiết bị · chưa kiểm tra dữ liệu trên tài khoản',
          ),
        FutureBuilder(
          future: c.codec.estimate(c.workspace),
          builder: (_, snapshot) => Text(
            snapshot.hasData
                ? '${snapshot.data!.decks} bộ thẻ · ${snapshot.data!.cards} thẻ'
                : 'Đang đọc thư viện…',
          ),
        ),
        const SizedBox(height: 16),
        Text(sync.status),
        if (sync.lastSynced != null)
          Text('Tiến độ học đã đồng bộ: ${syncDate(sync.lastSynced!)}'),
        if (sync.mediaStatus != null) Text(sync.mediaStatus!),
        if (sync.error != null && sync.error != sync.status)
          Text(
            sync.error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (sync.busy) const LinearProgressIndicator(),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed:
              !sync.available ||
                  sync.busy ||
                  busy ||
                  sync.needsMigration ||
                  sync.accountBlocked
              ? null
              : sync.requiresAuthentication
              ? () => run(onReauthenticate)
              : () => run(sync.syncNow),
          icon: const Icon(Icons.sync),
          label: Text(
            sync.requiresAuthentication
                ? 'Xác thực lại'
                : sync.error != null
                ? 'Thử lại đồng bộ'
                : sync.available && sync.lastSynced == null
                ? 'Đồng bộ để tải thư viện'
                : 'Đồng bộ ngay',
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tự động đồng bộ'),
          subtitle: const Text(
            'Trên thiết bị này, khi mở ứng dụng và có thay đổi.',
          ),
          value: sync.automatic,
          onChanged: !sync.available || busy
              ? null
              : (value) => run(() => sync.setAutomatic(value)),
        ),
        const Text(
          'Đồng bộ sau khi học trên máy này và trước khi học trên máy khác. Thay đổi chưa gửi vẫn được giữ trên thiết bị.',
        ),
        if (sync.needsMigration) ...[
          const Text(
            'Chọn dữ liệu ban đầu một lần, rồi đồng bộ để dùng chung thư viện giữa các thiết bị.',
          ),
          OutlinedButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    LegacyLibrariesScreen(controller: c, initializing: true),
              ),
            ),
            child: const Text('Chọn thư viện đang học'),
          ),
        ],
        if (sync.conflicts.isNotEmpty)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.compare_arrows),
            title: Text('${sync.conflicts.length} mục cần chọn nội dung'),
            subtitle: const Text('Cả hai bản chỉnh sửa đều được giữ lại.'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => SyncConflictsScreen(controller: sync),
              ),
            ),
          ),
        const SizedBox(height: 12),
        ExpansionTile(
          title: const Text('Nâng cao'),
          children: [
            ListTile(
              title: const Text('Lịch sử khôi phục'),
              leading: const Icon(Icons.history),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => RecoveryHistoryScreen(controller: c),
                ),
              ),
            ),
            ListTile(
              title: const Text('Dữ liệu cũ trên thiết bị'),
              leading: const Icon(Icons.phone_android),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => LegacyLibrariesScreen(controller: c),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

Future<void> _perform(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e is AccountFailure
                ? e.message
                : 'Chưa thực hiện được. Dữ liệu hiện tại được giữ.',
          ),
        ),
      );
    }
  }
}

Future<bool> _confirm(
  BuildContext context,
  String title,
  String message,
  String button,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(button),
          ),
        ],
      ),
    ) ??
    false;

class RecoveryHistoryScreen extends StatefulWidget {
  const RecoveryHistoryScreen({super.key, required this.controller});
  final AccountBackupController controller;
  @override
  State<RecoveryHistoryScreen> createState() => _RecoveryHistoryScreenState();
}

class _RecoveryHistoryScreenState extends State<RecoveryHistoryScreen> {
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    widget.controller.refreshCloud();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    await _perform(context, action);
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (_, _) {
      final c = widget.controller;
      return Scaffold(
        appBar: AppBar(title: const Text('Lịch sử khôi phục')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Text(
              'Chỉ khôi phục khi bạn cần quay lại dữ liệu trước đó. Việc học trên các thiết bị được cập nhật bằng Đồng bộ.',
            ),
            if (c.stale) const Text('Chưa tải được lịch sử mới nhất.'),
            if (_busy || c.cloudLoading) const LinearProgressIndicator(),
            TextButton(
              onPressed: _busy ? null : () => _run(c.refreshCloud),
              child: const Text('Tải lại lịch sử'),
            ),
            for (final b in c.backups.where((b) => b['status'] == 'ready'))
              ListTile(
                title: Text(
                  syncDate(
                    DateTime.fromMillisecondsSinceEpoch(b['snapshotAt'] as int),
                  ),
                ),
                subtitle: Text(
                  '${b['deckCount'] ?? '?'} bộ thẻ · ${b['cardCount'] ?? '?'} thẻ${b['automatic'] == true ? '' : ' · Bản sao cũ'}',
                ),
                trailing: PopupMenuButton<String>(
                  enabled: !_busy && !c.sync.busy,
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'restore',
                      child: Text('Xem và khôi phục'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Xóa điểm khôi phục'),
                    ),
                  ],
                  onSelected: (action) => _run(() async {
                    if (action == 'delete') {
                      if (!await _confirm(
                        context,
                        'Xóa điểm khôi phục?',
                        'Dữ liệu học hiện tại được giữ nguyên.',
                        'Xóa',
                      )) {
                        return;
                      }
                      await c.deleteBackup(b);
                    } else {
                      if (!await _confirm(
                        context,
                        'Khôi phục dữ liệu?',
                        '${syncDate(DateTime.fromMillisecondsSinceEpoch(b['snapshotAt'] as int))}\n${b['deckCount']} bộ thẻ · ${b['cardCount']} thẻ\n\nThư viện hiện tại sẽ được thay bằng nội dung này và đồng bộ sang các thiết bị khác. Một điểm khôi phục an toàn sẽ được tạo trước.',
                        'Khôi phục',
                      )) {
                        return;
                      }
                      await c.restoreIntoLibrary(b);
                    }
                  }),
                ),
              ),
            if (c.backups.isEmpty && !c.cloudLoading)
              const Text('Chưa có điểm khôi phục.'),
          ],
        ),
      );
    },
  );
}

class LegacyLibrariesScreen extends StatefulWidget {
  const LegacyLibrariesScreen({
    super.key,
    required this.controller,
    this.initializing = false,
  });
  final AccountBackupController controller;
  final bool initializing;
  @override
  State<LegacyLibrariesScreen> createState() => _LegacyLibrariesScreenState();
}

class _LegacyLibrariesScreenState extends State<LegacyLibrariesScreen> {
  bool _busy = false;
  late final _records = widget.controller.workspaces.available(
    widget.controller.account?.uid,
  );
  Future<({int decks, int cards})> _counts(WorkspaceRecord r) async {
    final context = WorkspaceContext(r, -5);
    try {
      final count = await widget.controller.codec.estimate(context);
      return (decks: count.decks, cards: count.cards);
    } finally {
      await context.revoke();
    }
  }

  Future<void> _choose(WorkspaceRecord? r) async {
    final c = widget.controller;
    if (_busy || c.sync.busy) return;
    if (!await _confirm(
      context,
      widget.initializing
          ? 'Dùng làm thư viện ban đầu?'
          : 'Thêm bài học vào tài khoản?',
      r == null
          ? 'Bắt đầu với thư viện trống. Các kho và bản sao cũ vẫn được giữ để khôi phục sau.'
          : '${r.name}\nDữ liệu nguồn vẫn được giữ trên thiết bị.',
      widget.initializing ? 'Dùng thư viện này' : 'Thêm bài học',
    )) {
      return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    await _perform(context, () async {
      if (widget.initializing) {
        await c.sync.acceptMigration(source: r);
      } else if (r != null) {
        await c.importLegacy(r);
      }
    });
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.initializing
            ? 'Chọn thư viện ban đầu'
            : 'Dữ liệu cũ trên thiết bị',
      ),
    ),
    body: FutureBuilder(
      future: _records,
      builder: (_, snapshot) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Chỉ thêm dữ liệu bạn muốn giữ. Các bản cũ không được tự gộp để tránh đưa bài đã xóa trở lại.',
          ),
          if (_busy) const LinearProgressIndicator(),
          for (final r in snapshot.data ?? <WorkspaceRecord>[])
            if (r.id != widget.controller.workspace.record.id)
              FutureBuilder(
                future: _counts(r),
                builder: (_, counts) => ListTile(
                  title: Text(r.name),
                  subtitle: Text(
                    counts.hasData
                        ? '${counts.data!.decks} bộ thẻ · ${counts.data!.cards} thẻ${r.ownerUid == null ? ' · Dữ liệu khách' : ''}'
                        : 'Đang đọc dữ liệu…',
                  ),
                  onTap: _busy || !counts.hasData ? null : () => _choose(r),
                ),
              ),
          if (widget.initializing) ...[
            OutlinedButton(
              onPressed: _busy ? null : () => _choose(null),
              child: const Text('Bắt đầu với thư viện trống'),
            ),
            TextButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      RecoveryHistoryScreen(controller: widget.controller),
                ),
              ),
              child: const Text('Xem bản sao từ thiết bị cũ'),
            ),
          ],
        ],
      ),
    ),
  );
}

class SyncConflictsScreen extends StatelessWidget {
  const SyncConflictsScreen({super.key, required this.controller});
  final SyncController controller;
  String _description(Map side) {
    if (side['deleted'] == true) return 'Đã xóa';
    final data = side['data'] as Map;
    return [
      for (final f in [
        'title',
        'front',
        'back',
        'raw_text',
        'normalized_text',
        'raw_full_text',
        'description',
      ])
        if (data[f] is String && (data[f] as String).isNotEmpty) data[f],
    ].join('\n');
  }

  Future<void> _edit(
    BuildContext context,
    Map<String, dynamic> conflict,
  ) async {
    final side = Map<String, dynamic>.from(conflict['local'] as Map);
    final data = Map<String, dynamic>.from(side['data'] as Map);
    if (conflict['table'] == 'cards') {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => CardEditorDialog(
          repository: LocalDeckRepository(),
          deckId: data['deck_id'] as String,
          card: local_io.LocalDeckRepository.cardFromRow({
            ...data,
            'due_date': data['created_at'],
          }),
          onSaveContent: (content) => controller.resolve(
            conflict,
            {...side, 'deleted': false},
            edited: {
              ...data,
              'type': content.type.wireName,
              'status': data['status'] == 'deleted' ? 'active' : data['status'],
              'front': content.front,
              'back': content.answer,
              'tags': jsonEncode(content.tags),
              'mcq_payload': content.type.wireName == 'MCQ'
                  ? jsonEncode({
                      'options': content.options
                          .map((o) => o.toJson())
                          .toList(),
                      'correctOptionId': content.correctOptionId,
                      'explanation': content.explanation,
                    })
                  : null,
            },
          ),
        ),
      );
    } else {
      final fields = <String, TextEditingController>{
        for (final f in [
          'title',
          'description',
          'raw_text',
          'normalized_text',
          'raw_full_text',
        ])
          if (data.containsKey(f))
            f: TextEditingController(text: data[f] as String?),
      };
      final edited = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Chỉnh sửa thành bản chung'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final e in fields.entries)
                  TextField(
                    controller: e.value,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: {
                        'title': 'Tên',
                        'description': 'Mô tả',
                        'raw_text': 'Văn bản',
                        'normalized_text': 'Văn bản đã chỉnh sửa',
                        'raw_full_text': 'Văn bản nhận dạng',
                      }[e.key],
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, {
                ...data,
                if (data['status'] == 'deleted')
                  'status': conflict['table'] == 'source_blocks'
                      ? 'user_added'
                      : 'active',
                for (final e in fields.entries) e.key: e.value.text,
              }),
              child: const Text('Lưu bản chung'),
            ),
          ],
        ),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final c in fields.values) {
          c.dispose();
        }
      });
      if (edited != null) {
        await controller.resolve(conflict, {
          ...side,
          'deleted': false,
        }, edited: edited);
      }
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (_, _) => Scaffold(
      appBar: AppBar(title: const Text('Chọn nội dung cần giữ')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Các thiết bị đã sửa cùng một nội dung. Tiến độ ôn và những bài khác vẫn được đồng bộ.',
          ),
          if (controller.conflicts.isEmpty)
            const Text('Đã xử lý tất cả xung đột.'),
          for (final c in controller.conflicts)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final pair in [
                      ('local', 'Bản chỉnh sửa gửi lên'),
                      ('remote', 'Bản đang dùng trong tài khoản'),
                    ]) ...[
                      Text(
                        pair.$2,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        'Thiết bị: ${(c[pair.$1] as Map)['deviceId'] ?? 'Không rõ'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(_description(c[pair.$1] as Map)),
                      TextButton(
                        onPressed: controller.busy
                            ? null
                            : () => _perform(
                                context,
                                () => controller.resolve(
                                  c,
                                  Map<String, dynamic>.from(c[pair.$1] as Map),
                                ),
                              ),
                        child: const Text('Giữ bản này'),
                      ),
                      const Divider(),
                    ],
                    OutlinedButton(
                      onPressed: controller.busy
                          ? null
                          : () => _perform(context, () => _edit(context, c)),
                      child: const Text('Chỉnh sửa thành bản chung'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

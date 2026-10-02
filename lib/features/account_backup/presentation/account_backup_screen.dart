import 'dart:async';

import 'package:flutter/material.dart';

import '../application/account_backup_controller.dart';
import '../domain/auth_repository.dart';

class AccountBackupScreen extends StatefulWidget {
  const AccountBackupScreen({super.key, required this.controller});
  final AccountBackupController controller;
  @override
  State<AccountBackupScreen> createState() => _AccountBackupScreenState();
}

class _AccountBackupScreenState extends State<AccountBackupScreen> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _register = false, _busy = false;
  AccountBackupController get c => widget.controller;
  @override
  void initState() {
    super.initState();
    c.accountScreens++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(c.refreshCloud());
    });
  }

  @override
  void dispose() {
    c.accountScreens--;
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) =>
      value == null ||
          !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? 'Nhập email hợp lệ'
      : null;
  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted)
        _notice(
          error is AccountFailure
              ? error.message
              : 'Không thể thực hiện thao tác. Dữ liệu cục bộ được giữ.',
        );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<bool> _ask(String title, String text, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _afterLogin() async {
    final account = c.account!;
    final owned = (await c.workspaces.available(account.uid))
        .where((w) => w.ownerUid == account.uid);
    var attach = false;
    if (mounted && c.workspace.record.ownerUid == null && owned.isEmpty) {
      final estimate = await c.codec.estimate(c.workspace);
      if (!mounted) return;
      attach = await _ask(
        'Gắn dữ liệu đang học trên thiết bị với tài khoản này?',
        '${account.email}\n${estimate.decks} deck · ${estimate.cards} card\nChưa gắn thì kho khách vẫn độc lập.',
        'Gắn và tiếp tục',
      );
    }
    await c.afterLogin(attachGuest: attach);
  }

  Future<void> _submit() => _run(() async {
    if (!_form.currentState!.validate()) return;
    if (_register) {
      await c.auth.register(_email.text, _password.text);
      // Account creation and email delivery are separate: never register twice.
      try {
        await c.auth.sendVerification();
      } on AccountFailure catch (error) {
        c.message =
            'Tài khoản đã tạo. ${error.message} Có thể gửi lại email xác minh.';
      }
    } else {
      await c.auth.signInEmail(_email.text, _password.text);
    }
    _password.clear();
    _confirm.clear();
    await _afterLogin();
  });
  Future<void> _backup() async {
    final estimate = await c.codec.estimate(c.workspace);
    if (!mounted) return;
    if (await _ask(
      'Sao lưu toàn kho riêng tư',
      '${estimate.decks} deck · ${estimate.cards} card\n${estimate.files} tệp · khoảng ${(estimate.bytes / 1048576).toStringAsFixed(1)} MiB\nDữ liệu đã lưu và ảnh/PDF sẽ được tải lên S3. Bạn có thể rời màn hình để tiếp tục học.\nGiới hạn: 100 MiB, 1.000 tệp, 5 bản mỗi kho, thời gian chờ 10 phút.',
      'Sao lưu',
    ))
      await c.backup();
  }

  Future<void> _signOut() => _run(() async {
    if (c.workspace.record.ownerUid != null && await c.hasChanges()) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Có dữ liệu chưa sao lưu'),
          content: const Text(
            'Dữ liệu riêng sẽ được giữ trên thiết bị và ẩn sau đăng xuất.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'backup'),
              child: const Text('Tiếp tục sao lưu'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'logout'),
              child: const Text('Đăng xuất'),
            ),
          ],
        ),
      );
      if (choice != 'logout') {
        if (choice == 'backup') await _backup();
        return;
      }
    }
    await c.signOut();
  });
  Future<void> _link(bool google) => _run(() async {
    final passwordProvider = c.account!.providers.contains('password');
    if (passwordProvider) {
      final credentials = await _credentials(newPassword: false);
      if (credentials == null) return;
      await c.auth.reauthenticate(password: credentials.$2);
    } else {
      await c.auth.reauthenticate();
    }
    if (google) {
      await c.auth.linkGoogle();
    } else {
      if (!mounted) return;
      final credentials = await _credentials(newPassword: true);
      if (credentials == null) return;
      await c.auth.linkEmail(credentials.$1, credentials.$2);
    }
  });
  Future<(String, String)?> _credentials({required bool newPassword}) async {
    final email = TextEditingController(text: c.account!.email),
        password = TextEditingController(),
        confirm = TextEditingController();
    final key = GlobalKey<FormState>();
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(newPassword ? 'Liên kết email/mật khẩu' : 'Xác thực lại'),
        content: Form(
          key: key,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (newPassword)
                TextFormField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: _validateEmail,
                ),
              TextFormField(
                controller: password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Mật khẩu'),
                validator: (v) =>
                    v == null || v.isEmpty || (newPassword && v.length < 8)
                    ? 'Nhập mật khẩu${newPassword ? ' ít nhất 8 ký tự' : ''}'
                    : null,
              ),
              if (newPassword)
                TextFormField(
                  controller: confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Xác nhận mật khẩu',
                  ),
                  validator: (v) => v != password.text
                      ? 'Mật khẩu xác nhận không khớp'
                      : null,
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
            onPressed: () {
              if (key.currentState!.validate())
                Navigator.pop(context, (email.text, password.text));
            },
            child: const Text('Tiếp tục'),
          ),
        ],
      ),
    );
    // Dialog exit animations still use controllers for one frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      email.dispose();
      password.dispose();
      confirm.dispose();
    });
    return result;
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: c,
    builder: (context, _) {
      final account = c.account;
      if (!c.accessAllowed)
        return Scaffold(
          appBar: AppBar(title: const Text('Tài khoản và sao lưu')),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(account?.email ?? 'Đã đăng xuất'),
              const Text('Kho trước thuộc tài khoản khác và đã được ẩn.'),
              if (c.message != null) Text(c.message!),
              FilledButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        if (account == null) {
                          await c.select(await c.workspaces.preferred(null));
                        } else {
                          await c.afterLogin(attachGuest: false);
                        }
                      }),
                child: const Text('Mở kho được phép truy cập'),
              ),
              TextButton(
                onPressed: _busy ? null : () => _run(c.signOut),
                child: const Text('Đăng xuất'),
              ),
            ],
          ),
        );
      return Scaffold(
        appBar: AppBar(title: const Text('Tài khoản và sao lưu')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (account == null) ...[
              const Text(
                'Học offline trên thiết bị hoặc đăng nhập để sao lưu kho riêng tư.',
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        final result = await c.auth.signInGoogle();
                        if (result != null) await _afterLogin();
                      }),
                icon: const Icon(Icons.account_circle_outlined),
                label: const Text('Đăng nhập bằng Google'),
              ),
              Form(
                key: _form,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: _validateEmail,
                    ),
                    TextFormField(
                      controller: _password,
                      obscureText: true,
                      decoration: const InputDecoration(labelText: 'Mật khẩu'),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Nhập mật khẩu'
                          : _register && v.length < 8
                          ? 'Mật khẩu mới tối thiểu 8 ký tự'
                          : null,
                    ),
                    if (_register)
                      TextFormField(
                        controller: _confirm,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Xác nhận mật khẩu',
                        ),
                        validator: (v) => v != _password.text
                            ? 'Mật khẩu xác nhận không khớp'
                            : null,
                      ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: Text(_register ? 'Tạo tài khoản' : 'Đăng nhập'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() => _register = !_register),
                child: Text(_register ? 'Quay lại đăng nhập' : 'Tạo tài khoản'),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        if (_validateEmail(_email.text) != null) {
                          _form.currentState!.validate();
                          return;
                        }
                        await c.auth.resetPassword(_email.text);
                        if (mounted)
                          _notice(
                            'Nếu email phù hợp với một tài khoản, bạn sẽ nhận được hướng dẫn đặt lại mật khẩu',
                          );
                      }),
                child: const Text('Quên mật khẩu'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tiếp tục học trên thiết bị'),
              ),
            ] else ...[
              Text(
                account.email,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                account.emailVerified
                    ? 'Đã xác minh email'
                    : 'Xác minh email để sao lưu',
              ),
              if (!account.emailVerified) ...[
                TextButton(
                  onPressed: _busy ? null : () => _run(c.auth.sendVerification),
                  child: const Text('Gửi lại email xác minh'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await c.auth.refresh();
                          await c.refreshCloud();
                        }),
                  child: const Text('Tôi đã xác minh'),
                ),
              ],
              const Divider(),
              Text(
                '${c.workspace.record.name} · ${c.workspace.record.ownerUid == null ? 'Kho khách chưa gắn' : 'Kho tài khoản'}',
              ),
              FutureBuilder(
                future: c.codec.estimate(c.workspace),
                builder: (context, snapshot) => Text(
                  snapshot.hasData
                      ? '${snapshot.data!.decks} deck · ${snapshot.data!.cards} card · ${snapshot.data!.files} tệp'
                      : 'Đang đọc kho…',
                ),
              ),
              FutureBuilder(
                future: c.workspaces.available(account.uid),
                builder: (context, snapshot) => DropdownButton<String>(
                  isExpanded: true,
                  value: c.workspace.record.id,
                  items: snapshot.data
                      ?.map(
                        (w) => DropdownMenuItem(
                          value: w.id,
                          child: Text(
                            '${w.name} (${w.ownerUid == null ? 'khách' : account.email})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (id) {
                          if (id != null)
                            _run(
                              () async => c.select(await c.workspaces.get(id)),
                            );
                        },
                ),
              ),
              if (c.workspace.record.ownerUid == null)
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          final estimate = await c.codec.estimate(c.workspace);
                          if (!mounted) return;
                          if (await _ask(
                            'Gắn kho khách?',
                            '${account.email}\n${estimate.decks} deck · ${estimate.cards} card\nKho này sẽ thuộc tài khoản trên.',
                            'Gắn và tiếp tục',
                          ))
                            await c.select(
                              await c.workspaces.attach(
                                c.workspace.record.id,
                                account.uid,
                              ),
                            );
                        }),
                  child: const Text('Gắn kho này với tài khoản'),
                ),
              Text(c.status),
              if (c.busy)
                LinearProgressIndicator(
                  value: c.progress > 0 ? c.progress : null,
                ),
              const Text(
                '100 MiB · 1.000 tệp · 5 bản/kho · thời gian chờ 10 phút',
              ),
              FilledButton.icon(
                onPressed: c.canBackup && !_busy ? () => _run(_backup) : null,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Sao lưu ngay / Thử lại'),
              ),
              TextButton(
                onPressed: _busy || c.cloudLoading
                    ? null
                    : () => _run(c.refreshCloud),
                child: const Text('Đối chiếu và tải lại danh sách'),
              ),
              if (c.stale)
                const Text(
                  'Thông tin cloud cũ; chưa được dịch vụ xác nhận lại.',
                ),
              for (final backup in c.backups)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    backup['status'] == 'ready'
                        ? 'Bản sao hoàn tất'
                        : 'Bản sao ${backup['status']}',
                  ),
                  subtitle: Text(
                    'Dữ liệu: ${DateTime.fromMillisecondsSinceEpoch(backup['snapshotAt'] as int).toLocal()}\n${backup['deckCount'] ?? '?'} deck · ${backup['cardCount'] ?? '?'} card · ${((backup['sizeBytes'] as num) / 1048576).toStringAsFixed(1)} MiB${backup['completedAt'] == null ? '' : '\nXác nhận: ${DateTime.fromMillisecondsSinceEpoch(backup['completedAt'] as int).toLocal()}'}',
                  ),
                  trailing: PopupMenuButton<String>(
                    enabled: !_busy,
                    onSelected: (action) => _run(() async {
                      if (action == 'delete') {
                        if (await _ask(
                          'Xóa bản sao?',
                          'Chỉ xóa bản cloud đã chọn; dữ liệu học trên thiết bị được giữ.',
                          'Xóa',
                        ))
                          await c.deleteBackup(backup);
                      } else {
                        if (!await _ask(
                          'Khôi phục vào kho mới?',
                          'Giữ nguyên kho đang học. Ngày dữ liệu: ${DateTime.fromMillisecondsSinceEpoch(backup['snapshotAt'] as int).toLocal()}',
                          'Khôi phục vào kho mới',
                        ))
                          return;
                        final restored = await c.restore(backup);
                        if (!mounted) return;
                        if (await _ask(
                          'Đã khôi phục',
                          'Chuyển sang kho vừa khôi phục?',
                          'Chuyển kho',
                        ))
                          await c.select(restored);
                      }
                    }),
                    itemBuilder: (_) => [
                      if (backup['status'] == 'ready')
                        const PopupMenuItem(
                          value: 'restore',
                          child: Text('Khôi phục'),
                        ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Text('Xóa bản sao'),
                      ),
                    ],
                  ),
                ),
              if (!account.providers.contains('google.com'))
                TextButton(
                  onPressed: _busy ? null : () => _link(true),
                  child: const Text('Liên kết Google'),
                ),
              if (!account.providers.contains('password'))
                TextButton(
                  onPressed: _busy ? null : () => _link(false),
                  child: const Text('Liên kết email/mật khẩu'),
                ),
              TextButton(
                onPressed: _busy ? null : _signOut,
                child: const Text('Đăng xuất'),
              ),
            ],
            if (c.message != null) Text(c.message!),
            if (_busy) const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    },
  );
}

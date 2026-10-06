import 'dart:async';

import 'package:flutter/material.dart';

import '../application/account_backup_controller.dart';
import '../domain/auth_repository.dart';
import '../../sync/presentation/sync_widgets.dart';
import '../../sync/data/local_sync_store.dart';

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
      if (mounted) {
        _notice(
          error is AccountFailure
              ? error.message
              : 'Không thể thực hiện thao tác. Dữ liệu cục bộ được giữ.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _notice(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<bool> _ask(
    String title,
    String text,
    String action, {
    String cancel = 'Hủy',
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(cancel),
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
    var attach = false;
    if (c.account!.emailVerified && c.workspace.record.ownerUid == null) {
      final guestStore = LocalSyncStore(c.workspace);
      final choiceKey = 'guestChoice.${c.account!.uid}';
      final previousChoice = await guestStore.setting(choiceKey);
      final count = await c.codec.estimate(c.workspace);
      if (!mounted) return;
      if (previousChoice == null &&
          (count.decks > 0 || count.cards > 0 || count.files > 0)) {
        attach = await _ask(
          'Thêm bài học trên thiết bị vào tài khoản?',
          '${c.account!.email}\n${count.decks} bộ thẻ · ${count.cards} thẻ',
          'Thêm vào tài khoản',
          cancel: 'Giữ riêng trên thiết bị',
        );
        await guestStore.setSetting(choiceKey, attach ? 'merged' : 'private');
      }
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
    if (mounted) {
      _password.clear();
      _confirm.clear();
    }
    await _afterLogin();
  });
  Future<void> _signOut() => _run(() async {
    if (await c.sync.hasPending) {
      if (!mounted) return;
      final choice = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Có thay đổi chưa đồng bộ'),
          content: const Text(
            'Thay đổi chưa gửi vẫn được giữ trên thiết bị sau khi đăng xuất.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'keep'),
              child: const Text('Đăng xuất và giữ trên thiết bị'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, 'sync'),
              child: const Text('Đồng bộ rồi đăng xuất'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      if (choice == 'sync') {
        await c.sync.syncNow();
        if (c.sync.busy ||
            await c.sync.hasPending ||
            c.sync.error != null ||
            c.sync.needsMigration) {
          if (mounted) {
            _notice(
              'Chưa đồng bộ xong. Hãy thử lại hoặc đăng xuất và giữ trên thiết bị.',
            );
          }
          return;
        }
      }
    }
    await c.signOut();
  });
  Future<void> _reauthenticateAndSync() async {
    final uid = c.account?.uid;
    if (uid == null) return;
    if (c.account!.providers.contains('password')) {
      final credentials = await _credentials(newPassword: false);
      if (credentials == null) return;
      await c.auth.reauthenticate(password: credentials.$2);
    } else {
      await c.auth.reauthenticate();
    }
    if (c.account?.uid != uid) return;
    await c.sync.syncNow();
  }

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
              if (key.currentState!.validate()) {
                Navigator.pop(context, (email.text, password.text));
              }
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
      if (!c.accessAllowed) {
        return Scaffold(
          appBar: AppBar(title: const Text('Tài khoản và đồng bộ')),
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
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Tài khoản và đồng bộ')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (account == null) ...[
              const Text(
                'Học offline hoặc đăng nhập để đồng bộ tiến độ giữa các thiết bị.',
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
                        if (mounted) {
                          _notice(
                            'Nếu email phù hợp với một tài khoản, bạn sẽ nhận được hướng dẫn đặt lại mật khẩu',
                          );
                        }
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
                    : 'Xác minh email để đồng bộ',
              ),
              if (c.message != null) Text(c.message!),
              if (!account.emailVerified ||
                  c.sync.failureCode == 'email_unverified') ...[
                TextButton(
                  onPressed: _busy ? null : () => _run(c.auth.sendVerification),
                  child: const Text('Gửi lại email xác minh'),
                ),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _run(() async {
                          await c.auth.refresh();
                          if (c.account?.emailVerified == true) {
                            await _afterLogin();
                          }
                        }),
                  child: const Text('Tôi đã xác minh'),
                ),
              ],
              SyncAccountPanel(
                controller: c,
                run: _run,
                onReauthenticate: _reauthenticateAndSync,
                busy: _busy,
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
            if (account == null && c.message != null) Text(c.message!),
            if (_busy) const Center(child: CircularProgressIndicator()),
          ],
        ),
      );
    },
  );
}

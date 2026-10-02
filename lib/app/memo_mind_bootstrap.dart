import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/workspace/workspace_context.dart';
import '../features/account_backup/data/firebase_auth_repository.dart';
import '../features/account_backup/domain/auth_repository.dart';
import '../features/account_backup/application/account_backup_controller.dart';
import '../features/account_backup/presentation/account_backup_screen.dart';
import 'app.dart';

class MemoMindBootstrap extends StatefulWidget {
  const MemoMindBootstrap({super.key});
  @override
  State<MemoMindBootstrap> createState() => _MemoMindBootstrapState();
}

class _MemoMindBootstrapState extends State<MemoMindBootstrap> {
  AccountBackupController? _account;
  String? _error;
  int _generation = -1;
  bool _reopenAccount = false;
  bool _accessAllowed = true;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _generation = 0);
      return;
    }
    try {
      AuthRepository auth = const UnconfiguredAuthRepository();
      const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
      if (project.isNotEmpty) {
        try {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
              appId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
              messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
              projectId: project,
            ),
          );
          auth = FirebaseAuthRepository(FirebaseAuth.instance);
        } catch (_) {
          /* Cloud setup cannot prevent offline learning. */
        }
      }
      final workspaces = WorkspaceRepository();
      await workspaces.initialize(uid: auth.current?.uid);
      final account = AccountBackupController(
        auth: auth,
        workspaces: workspaces,
      );
      account.addListener(_changed);
      if (!mounted) return;
      setState(() {
        _account = account;
        _generation = workspaces.current!.generation;
        _error = null;
      });
    } catch (_) {
      if (mounted)
        setState(
          () => _error =
              'Không thể mở kho dữ liệu. Dữ liệu cũ được giữ; hãy thử lại.',
        );
    }
  }

  void _changed() {
    final next = _account!.workspace.generation;
    final access = _account!.accessAllowed;
    if (!mounted || (next == _generation && access == _accessAllowed)) return;
    setState(() {
      _reopenAccount = _account!.accountScreenVisible;
      _generation = next;
      _accessAllowed = access;
    });
  }

  @override
  void dispose() {
    _account?.removeListener(_changed);
    _account?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_accessAllowed && _account != null)
      return MaterialApp(home: AccountBackupScreen(controller: _account!));
    if (_generation >= 0)
      return MemoMindApp(
        key: ValueKey(_generation),
        account: _account,
        reopenAccount: _reopenAccount,
      );
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_error!),
                    TextButton(
                      onPressed: _initialize,
                      child: const Text('Thử lại'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

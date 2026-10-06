import 'package:flutter/foundation.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../core/workspace/workspace_context.dart';
import '../features/account_backup/data/firebase_auth_repository.dart';
import '../features/account_backup/domain/auth_repository.dart';
import '../features/account_backup/application/account_backup_controller.dart';
import '../features/account_backup/presentation/account_backup_screen.dart';
import '../shared/theme/memo_theme.dart';
import 'app.dart';
import 'startup_welcome_controller.dart';
import 'startup_welcome_gate.dart';

class MemoMindBootstrap extends StatefulWidget {
  const MemoMindBootstrap({super.key});
  @override
  State<MemoMindBootstrap> createState() => _MemoMindBootstrapState();
}

class _MemoMindBootstrapState extends State<MemoMindBootstrap> {
  AccountBackupController? _account;
  final _welcome = StartupWelcomeController();
  bool _initializing = false;
  int _generation = -1;
  bool _reopenAccount = false;
  bool _accessAllowed = true;
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing || !mounted) return;
    _initializing = true;
    _welcome.markWaiting();
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      setState(() => _generation = 0);
      _initializing = false;
      return;
    }
    try {
      AuthRepository auth = const UnconfiguredAuthRepository();
      const project = String.fromEnvironment('FIREBASE_PROJECT_ID');
      try {
        if (project.isNotEmpty) {
          await Firebase.initializeApp(
            options: const FirebaseOptions(
              apiKey: String.fromEnvironment('FIREBASE_API_KEY'),
              appId: String.fromEnvironment('FIREBASE_ANDROID_APP_ID'),
              messagingSenderId: String.fromEnvironment('FIREBASE_SENDER_ID'),
              projectId: project,
            ),
          );
        } else {
          // Android resources are generated from google-services.json by Gradle.
          await Firebase.initializeApp();
        }
        auth = FirebaseAuthRepository(FirebaseAuth.instance);
      } catch (_) {
        /* Cloud setup cannot prevent offline learning. */
      }
      final workspaces = WorkspaceRepository();
      await workspaces.initialize(uid: auth.current?.uid);
      final account = AccountBackupController(
        auth: auth,
        workspaces: workspaces,
      );
      if (!mounted) {
        account.dispose();
        return;
      }
      account.addListener(_changed);
      setState(() {
        _account = account;
        _generation = workspaces.current!.generation;
      });
      if (auth.current?.emailVerified == true) {
        unawaited(
          account.afterLogin(attachGuest: false).catchError((Object _) {
            account.message = 'Chưa mở được thư viện đồng bộ. Dữ liệu trên thiết bị được giữ.';
          }),
        );
      }
    } catch (_) {
      if (mounted) {
        _welcome.fail(
          'Không thể mở kho dữ liệu. Dữ liệu cũ được giữ; hãy thử lại.',
        );
      }
    } finally {
      _initializing = false;
    }
  }

  void _changed() {
    final next = _account!.workspace.generation;
    final access = _account!.accessAllowed;
    if (!mounted || (next == _generation && access == _accessAllowed)) return;
    _welcome.markWaiting();
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
    _welcome.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StartupWelcomeGate(
      controller: _welcome,
      onRetry: _initialize,
      child: _content(),
    );
  }

  Widget _content() {
    if (!_accessAllowed && _account != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_accessAllowed) _welcome.markReady();
      });
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: MemoTheme.light,
        darkTheme: MemoTheme.dark,
        home: AccountBackupScreen(controller: _account!),
      );
    }
    if (_generation >= 0) {
      final generation = _generation;
      return MemoMindApp(
        key: ValueKey(generation),
        account: _account,
        reopenAccount: _reopenAccount,
        startupRevealed: _welcome.startupRevealed,
        onStartupReady: () {
          if (mounted && _generation == generation) _welcome.markReady();
        },
      );
    }
    return const SizedBox.expand();
  }
}

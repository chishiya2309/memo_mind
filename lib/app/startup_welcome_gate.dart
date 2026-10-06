import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../shared/theme/memo_theme.dart';
import 'startup_welcome_controller.dart';
import 'welcome_screen.dart';

/// Keeps the app mounted throughout the welcome and its fade-out.
class StartupWelcomeGate extends StatefulWidget {
  const StartupWelcomeGate({
    super.key,
    required this.controller,
    required this.child,
    required this.onRetry,
  });

  final StartupWelcomeController controller;
  final Widget child;
  final VoidCallback onRetry;

  @override
  State<StartupWelcomeGate> createState() => _StartupWelcomeGateState();
}

class _StartupWelcomeGateState extends State<StartupWelcomeGate>
    with SingleTickerProviderStateMixin {
  late final AnimationController _exit =
      AnimationController(
        vsync: this,
        value: 1,
        duration: const Duration(milliseconds: 250),
      )..addStatusListener((status) {
        if (status == AnimationStatus.dismissed) widget.controller.reveal();
      });
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_syncExit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.start();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncExit();
    });
  }

  void _syncExit() {
    final controller = widget.controller;
    if (!controller.visible) return;
    if (!controller.canReveal) {
      _exit.stop();
      _exit.value = 1;
    } else if (_reduceMotion) {
      controller.reveal();
    } else if (!_exit.isAnimating) {
      _exit.reverse();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_syncExit);
    _exit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.controller,
    builder: (context, _) {
      final visible = widget.controller.visible;
      return Stack(
        fit: StackFit.expand,
        alignment: Alignment.center,
        children: [
          ExcludeSemantics(
            excluding: visible,
            child: ExcludeFocus(
              excluding: visible,
              child: IgnorePointer(ignoring: visible, child: widget.child),
            ),
          ),
          if (visible)
            FadeTransition(
              opacity: _exit,
              child: MaterialApp(
                title: 'MemoMind',
                debugShowCheckedModeBanner: false,
                locale: const Locale('vi'),
                supportedLocales: const [Locale('vi')],
                localizationsDelegates: GlobalMaterialLocalizations.delegates,
                theme: MemoTheme.light,
                darkTheme: MemoTheme.dark,
                home: WelcomeScreen(
                  waiting: widget.controller.waiting,
                  error: widget.controller.error,
                  onRetry: widget.onRetry,
                ),
              ),
            ),
        ],
      );
    },
  );
}

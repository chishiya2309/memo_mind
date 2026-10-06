import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../shared/branding/memo_mark.dart';
import '../shared/theme/memo_theme.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({
    super.key,
    this.waiting = false,
    this.error,
    this.onRetry,
  });

  final bool waiting;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _entrance.stop();
      _entrance.value = 1;
    }
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = MemoPalette.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
          .copyWith(
            statusBarColor: Colors.transparent,
            systemNavigationBarColor: p.background,
          ),
      child: Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  widget.error != null ||
                  constraints.maxHeight < 620 ||
                  constraints.maxWidth < 340 ||
                  MediaQuery.textScalerOf(context).scale(16) > 24;
              final logo = _logo(dark, compact ? 112 : 144);
              final words = _words(context, p);
              final status = _status(p);
              if (compact) {
                return SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          logo,
                          const SizedBox(height: 28),
                          words,
                          if (status != null) ...[
                            const SizedBox(height: 32),
                            status,
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }
              // Align with the native splash; text never shifts the icon.
              return Stack(
                alignment: Alignment.center,
                children: [
                  Center(child: logo),
                  Positioned(
                    top: constraints.maxHeight / 2 + 100,
                    left: 24,
                    right: 24,
                    child: words,
                  ),
                  if (status != null)
                    Positioned(bottom: 24, left: 24, right: 24, child: status),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _logo(bool dark, double size) => AnimatedBuilder(
    animation: _entrance,
    builder: (context, _) {
      final t = _entrance.value;
      final glow = Curves.easeOut.transform(t);
      final sparkle = t < .35
          ? .65 + t
          : t < .7
          ? 1 - (t - .35) * .5
          : .825 + (t - .7) * .175 / .3;
      return SizedBox.square(
        dimension: size * 1.8,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    colors: [
                      const Color(0xFF7C3AED)
                          .withValues(alpha: (dark ? .24 : .13) * glow),
                      const Color(0xFF7C3AED).withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            MemoMark(size: size, sparkle: sparkle),
          ],
        ),
      );
    },
  );

  Widget _words(BuildContext context, MemoPalette p) => FadeTransition(
    opacity: _entrance.drive(
      CurveTween(curve: const Interval(.25, 1, curve: Curves.easeOut)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'MemoMind',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'BeVietnamPro',
            fontSize: 36,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.2,
            color: p.text,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Học thông minh. Nhớ lâu hơn.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, height: 1.6, color: p.textMuted),
        ),
      ],
    ),
  );

  Widget? _status(MemoPalette p) {
    if (widget.error != null) {
      return Semantics(
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: p.error, height: 1.5),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: widget.onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Thử lại'),
            ),
          ],
        ),
      );
    }
    if (!widget.waiting) return null;
    return Semantics(
      liveRegion: true,
      child: Text(
        'Đang chuẩn bị không gian học…',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: p.textMuted, height: 1.5),
      ),
    );
  }
}

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/app/startup_welcome_controller.dart';
import 'package:memo_mind/app/startup_welcome_gate.dart';
import 'package:memo_mind/app/welcome_screen.dart';
import 'package:memo_mind/shared/branding/memo_mark.dart';
import 'package:memo_mind/shared/theme/memo_theme.dart';

void main() {
  Future<void> mount(
    WidgetTester tester,
    StartupWelcomeController controller, {
    VoidCallback? onRetry,
    Widget? child,
  }) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    });
    await tester.pumpWidget(
      StartupWelcomeGate(
        controller: controller,
        onRetry: onRetry ?? () {},
        child: child ?? const MaterialApp(home: Scaffold(body: Text('Home'))),
      ),
    );
  }

  Future<void> finishFade(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    // A ticker completes on the first frame strictly after its duration.
    await tester.pump(const Duration(milliseconds: 1));
  }

  testWidgets('fast startup keeps welcome for two seconds and then fades', (
    tester,
  ) async {
    final controller = StartupWelcomeController()..markReady();
    var revealed = false;
    controller.startupRevealed.then((_) => revealed = true);
    await mount(tester, controller);
    expect(find.text('Học thông minh. Nhớ lâu hơn.'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(controller.visible, isTrue);
    expect(revealed, isFalse);
    await tester.pump(const Duration(milliseconds: 1));
    expect(controller.visible, isTrue);
    await tester.pump(const Duration(milliseconds: 125));
    expect(revealed, isFalse);
    await tester.pump(const Duration(milliseconds: 125));
    await tester.pump(const Duration(milliseconds: 1));
    expect(revealed, isTrue);
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('slow startup settles its animation and waits for local data', (
    tester,
  ) async {
    final controller = StartupWelcomeController();
    await mount(tester, controller);
    await tester.pump(const Duration(seconds: 5));
    expect(controller.visible, isTrue);
    expect(find.text('Đang chuẩn bị không gian học…'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    controller.markReady();
    await finishFade(tester);
    expect(controller.visible, isFalse);
  });

  testWidgets('workspace error is retryable without repeating the delay', (
    tester,
  ) async {
    final controller = StartupWelcomeController();
    var retries = 0;
    await mount(
      tester,
      controller,
      onRetry: () {
        retries++;
        controller.markWaiting();
        controller.start();
      },
    );
    controller.fail('Không thể mở kho dữ liệu. Hãy thử lại.');
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Thử lại'), findsOneWidget);
    expect(controller.visible, isTrue);
    await tester.tap(find.text('Thử lại'));
    await tester.pump();
    expect(retries, 1);
    expect(find.text('Đang chuẩn bị không gian học…'), findsOneWidget);
    controller.markReady();
    await finishFade(tester);
    expect(controller.visible, isFalse);
  });

  testWidgets('workspace changes during the fade wait for the new dashboard', (
    tester,
  ) async {
    final controller = StartupWelcomeController()..markReady();
    await mount(tester, controller);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 100));
    controller.markWaiting();
    await tester.pump(const Duration(seconds: 1));
    expect(controller.visible, isTrue);
    controller.markReady();
    await finishFade(tester);
    expect(controller.visible, isFalse);
  });

  testWidgets('workspace changes and resume never replay the welcome', (
    tester,
  ) async {
    final controller = StartupWelcomeController()..markReady();
    final generation = ValueNotifier<int>(0);
    addTearDown(generation.dispose);
    await mount(
      tester,
      controller,
      child: ValueListenableBuilder<int>(
        valueListenable: generation,
        builder: (_, value, _) => MaterialApp(
          key: ValueKey(value),
          home: Scaffold(body: Text('Workspace $value')),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await finishFade(tester);
    controller.markWaiting();
    generation.value = 1;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.text('Workspace 1'), findsOneWidget);
  });

  testWidgets('underlying app stays mounted and cannot receive welcome taps', (
    tester,
  ) async {
    final controller = StartupWelcomeController()..markReady();
    var taps = 0;
    await mount(
      tester,
      controller,
      child: MaterialApp(
        home: Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('Study'),
            ),
          ),
        ),
      ),
    );
    await tester.tapAt(tester.getCenter(find.text('Study')));
    expect(taps, 0);
    await tester.pump(const Duration(seconds: 2));
    await finishFade(tester);
    await tester.tap(find.text('Study'));
    expect(taps, 1);
  });

  testWidgets('reduced motion keeps the two-second delay without a fade', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final controller = StartupWelcomeController()..markReady();
    await mount(tester, controller);
    await tester.pump(const Duration(milliseconds: 1999));
    expect(controller.visible, isTrue);
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    expect(controller.visible, isFalse);
  });

  testWidgets('disposing during startup cancels pending timers and tickers', (
    tester,
  ) async {
    final controller = StartupWelcomeController();
    await tester.pumpWidget(
      StartupWelcomeGate(
        controller: controller,
        onRetry: () {},
        child: const SizedBox.expand(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await tester.pump(const Duration(seconds: 3));
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.0, 3.0]) {
      testWidgets('welcome layout: dark=$dark, text scale=$scale', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            theme: dark ? MemoTheme.dark : MemoTheme.light,
            builder: (_, child) => MediaQuery(
              data: MediaQueryData(
                textScaler: TextScaler.linear(scale),
                disableAnimations: true,
              ),
              child: child!,
            ),
            home: const WelcomeScreen(
              error:
                  'Không thể mở kho dữ liệu. Dữ liệu cũ được giữ; hãy thử lại.',
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
        expect(
          scaffold.backgroundColor,
          dark ? MemoPalette.dark.background : MemoPalette.light.background,
        );
        await tester.ensureVisible(find.text('Thử lại'));
        expect(find.text('MemoMind'), findsOneWidget);
      });
    }
  }

  // Optional review artifacts; normal test runs do not write screenshots.
  if (Platform.environment['MEMOMIND_BRAND_PREVIEW'] == '1') {
    testWidgets('export welcome and launcher review images', (tester) async {
      await tester.runAsync(() async {
        final font = FontLoader('BeVietnamPro');
        for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
          font.addFont(
            rootBundle.load('assets/fonts/BeVietnamPro-$weight.ttf'),
          );
        }
        await font.load();
      });
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final boundaryKey = GlobalKey();
      for (final dark in [false, true]) {
        await tester.pumpWidget(
          RepaintBoundary(
            key: boundaryKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: dark ? MemoTheme.dark : MemoTheme.light,
              home: const WelcomeScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = (await image.toByteData(
            format: ui.ImageByteFormat.png,
          ))!;
          final file = File(
            'build/branding/welcome_${dark ? 'dark' : 'light'}.png',
          );
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        const MemoMarkPainter().paint(Canvas(recorder), const Size(1024, 1024));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1024, 1024);
        final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        await File('build/branding/memo_mind_icon.png')
            .writeAsBytes(bytes.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      });
    });
  }
}

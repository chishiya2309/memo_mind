import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:memo_mind/features/document_import/domain/document_import_models.dart';
import 'package:memo_mind/features/document_import/presentation/source_raster_view.dart';

class _RegionPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => canvas.drawRect(
    Rect.fromLTWH(
      size.width * .2,
      size.height * .2,
      size.width * .4,
      size.height * .4,
    ),
    Paint()..color = Colors.orange,
  );
  @override
  bool shouldRepaint(_RegionPainter oldDelegate) => false;
}

void main() {
  for (final portrait in [true, false]) {
    testWidgets(
      'raster, overlay and taps share bounds with ${portrait ? 'horizontal' : 'vertical'} margins and zoom',
      (tester) async {
        late Directory root;
        late File file;
        await tester.runAsync(() async {
          root = await Directory.systemTemp.createTemp('source-raster-');
          file = File('${root.path}/raster.png');
          await file.writeAsBytes(
            img.encodePng(
              img.Image(
                width: portrait ? 100 : 200,
                height: portrait ? 200 : 100,
              ),
            ),
          );
        });
        final controller = TransformationController();
        final taps = <Offset>[];
        final image = SourceImage(
          path: file.path,
          width: portrait ? 100 : 200,
          height: portrait ? 200 : 100,
          sha256: 'fixture',
        );
        try {
          await tester.runAsync(() async {
            await tester.pumpWidget(
              MaterialApp(
                theme: ThemeData.dark(),
                home: Scaffold(
                  body: Center(
                    child: SizedBox(
                      key: const Key('source-viewport'),
                      width: 600,
                      height: 320,
                      child: InteractiveViewer(
                        transformationController: controller,
                        child: SourceRasterView(
                          image: image,
                          painter: _RegionPainter(),
                          highlightKey: const Key('overlay'),
                          onTap: (point, size) => taps.add(
                            Offset(
                              point.dx / size.width,
                              point.dy / size.height,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            await precacheImage(
              FileImage(file),
              tester.element(find.byType(SourceRasterView)),
            );
          });
          await tester.pumpAndSettle();
          final rect = tester.getRect(find.byType(Image));
          final outer = tester.getRect(
            find.byKey(const Key('source-viewport')),
          );
          expect(
            rect.size,
            portrait ? const Size(160, 320) : const Size(600, 300),
          );
          expect(tester.getRect(find.byKey(const Key('overlay'))), rect);
          await tester.tapAt(
            portrait
                ? outer.topLeft + const Offset(5, 5)
                : Offset(outer.center.dx, outer.top + 2),
          );
          expect(taps, isEmpty);
          await tester.tapAt(
            rect.topLeft + Offset(rect.width * .25, rect.height * .75),
          );
          expect(taps.single.dx, closeTo(.25, 1e-6));
          expect(taps.single.dy, closeTo(.75, 1e-6));
          controller.value = Matrix4.diagonal3Values(1.25, 1.25, 1)
            ..setTranslationRaw(-60, -40, 0);
          await tester.pump();
          final zoomed = tester.getRect(find.byType(Image));
          expect(tester.getRect(find.byKey(const Key('overlay'))), zoomed);
          await tester.tapAt(zoomed.center);
          expect(taps.last.dx, closeTo(.5, 1e-6));
          expect(taps.last.dy, closeTo(.5, 1e-6));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
          await tester.runAsync(() => root.delete(recursive: true));
        }
      },
    );
  }
}

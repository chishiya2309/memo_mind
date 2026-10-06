import 'package:flutter/material.dart';

/// The 108-unit geometry is shared with Android's ic_memo_mark drawable.
class MemoMark extends StatelessWidget {
  const MemoMark({super.key, this.size = 144, this.sparkle = 1});

  final double size;
  final double sparkle;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Biểu tượng MemoMind',
    image: true,
    child: SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: MemoMarkPainter(sparkle: sparkle)),
    ),
  );
}

class MemoMarkPainter extends CustomPainter {
  const MemoMarkPainter({this.sparkle = 1});

  final double sparkle;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 108, size.height / 108);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0, 0, 108, 108),
        const Radius.circular(26),
      ),
      Paint()..color = const Color(0xFF4F46E5),
    );
    canvas.translate(54, 54);
    canvas.scale(.85);
    canvas.translate(-54, -54);
    canvas.save();
    canvas.translate(43, 55);
    canvas.rotate(-12 * 3.141592653589793 / 180);
    canvas.translate(-43, -55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(26, 32, 34, 46),
        const Radius.circular(5),
      ),
      Paint()..color = Colors.white.withValues(alpha: .24),
    );
    canvas.restore();
    final cards = Path()
      ..moveTo(31, 70)
      ..lineTo(31, 39)
      ..quadraticBezierTo(31, 34, 36, 34)
      ..lineTo(40, 34)
      ..quadraticBezierTo(42, 34, 44, 37)
      ..lineTo(54, 52)
      ..lineTo(64, 37)
      ..quadraticBezierTo(66, 34, 68, 34)
      ..lineTo(72, 34)
      ..quadraticBezierTo(77, 34, 77, 39)
      ..lineTo(77, 70)
      ..quadraticBezierTo(77, 75, 72, 75)
      ..lineTo(66, 75)
      ..lineTo(66, 51)
      ..lineTo(57, 65)
      ..quadraticBezierTo(54, 69, 51, 65)
      ..lineTo(42, 51)
      ..lineTo(42, 75)
      ..lineTo(36, 75)
      ..quadraticBezierTo(31, 75, 31, 70)
      ..close();
    canvas.drawPath(cards, Paint()..color = Colors.white);
    final star = Path()
      ..moveTo(73, 23)
      ..lineTo(75, 28)
      ..lineTo(80, 30)
      ..lineTo(75, 32)
      ..lineTo(73, 37)
      ..lineTo(71, 32)
      ..lineTo(66, 30)
      ..lineTo(71, 28)
      ..close();
    canvas.drawPath(
      star,
      Paint()..color = Colors.white.withValues(alpha: sparkle.clamp(0, 1)),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(MemoMarkPainter oldDelegate) =>
      sparkle != oldDelegate.sparkle;
}

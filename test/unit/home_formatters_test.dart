import 'package:flutter_test/flutter_test.dart';
import 'package:memo_mind/features/home/domain/home_dashboard_data.dart';
import 'package:memo_mind/features/home/presentation/home_formatters.dart';

void main() {
  test('Vietnamese greeting changes at the specified hour boundaries', () {
    DateTime at(int hour, int minute) => DateTime(2026, 9, 22, hour, minute);

    expect(greetingFor(at(4, 59)), 'Chào buổi tối');
    expect(greetingFor(at(5, 0)), 'Chào buổi sáng');
    expect(greetingFor(at(11, 59)), 'Chào buổi sáng');
    expect(greetingFor(at(12, 0)), 'Chào buổi chiều');
    expect(greetingFor(at(17, 59)), 'Chào buổi chiều');
    expect(greetingFor(at(18, 0)), 'Chào buổi tối');
    expect(vietnameseDate(at(9, 0)), 'Thứ Ba, 22 tháng 9');
  });

  test('review plan shows remaining cards after completed reviews', () {
    const plan = ReviewPlan(
      totalToday: 18,
      reviewedToday: 7,
      deckCount: 3,
      estimatedMinutes: 8,
    );
    expect(plan.remaining, 11);
    expect(plan.progress, closeTo(7 / 18, 0.0001));
  });
}

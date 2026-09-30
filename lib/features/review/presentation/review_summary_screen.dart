import 'package:flutter/material.dart';

import '../domain/review_models.dart';

class ReviewSummary extends StatelessWidget {
  const ReviewSummary({super.key, required this.snapshot});
  final ReviewSnapshot snapshot;
  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.task_alt,
            size: 64,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            snapshot.session.status == 'completed'
                ? 'Hoàn thành phiên ôn'
                : 'Đã kết thúc phiên',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          Text(
            '${snapshot.reviewedCards} thẻ đã ôn • ${snapshot.events.length} lượt đánh giá',
          ),
          const SizedBox(height: 24),
          for (final rating in ReviewRating.values)
            ListTile(
              title: Text(rating.label),
              trailing: Text('${snapshot.count(rating)}'),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Hoàn tất'),
          ),
        ],
      ),
    ),
  );
}

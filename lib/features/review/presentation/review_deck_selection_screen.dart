import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/local_review_repository.dart';
import '../domain/review_models.dart';
import '../domain/review_repository.dart';
import 'review_session_screen.dart';

class ReviewDeckSelectionScreen extends StatefulWidget {
  const ReviewDeckSelectionScreen({
    super.key,
    this.repository,
    this.dueOnly = false,
  });
  final ReviewRepository? repository;
  final bool dueOnly;
  @override
  State<ReviewDeckSelectionScreen> createState() =>
      _ReviewDeckSelectionScreenState();
}

class _ReviewDeckSelectionScreenState extends State<ReviewDeckSelectionScreen> {
  late final repository = widget.repository ?? LocalReviewRepository();
  late Future<List<ReviewDeck>> decks = repository.getDecks();
  late bool _dueOnly = widget.dueOnly;

  void _reloadDecks() {
    if (!mounted) return;
    final nextDecks = repository.getDecks();
    // Handle an early error before the next frame attaches FutureBuilder.
    // FutureBuilder still receives the error and displays the retry action.
    nextDecks.ignore();
    setState(() {
      decks = nextDecks;
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_dueOnly ? 'Bộ thẻ đến hạn' : 'Chọn bộ thẻ để ôn'),
    ),
    body: kIsWeb && widget.repository == null
        ? const Center(
            child: Text('Ôn tập ngoại tuyến hiện hỗ trợ trên Android.'),
          )
        : FutureBuilder<List<ReviewDeck>>(
            future: decks,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: _reloadDecks,
                    child: const Text('Không thể tải bộ thẻ. Thử lại'),
                  ),
                );
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final items = snapshot.data!
                  .where((d) => !_dueOnly || d.dueCount > 0)
                  .toList();
              if (items.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _dueOnly
                            ? 'Hiện không có thẻ đến hạn'
                            : 'Chưa có bộ thẻ. Hãy tạo học liệu trước.',
                      ),
                      if (_dueOnly)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _dueOnly = false;
                            });
                          },
                          child: const Text('Ôn tự do'),
                        ),
                    ],
                  ),
                );
              }
              return ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final deck = items[index];
                  return ListTile(
                    title: Text(deck.title),
                    subtitle: Text(
                      '${deck.activeCount} thẻ • ${deck.dueCount} đến hạn',
                    ),
                    trailing: const Icon(Icons.play_circle_outline),
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ReviewSessionScreen(
                            repository: repository,
                            deckId: deck.id,
                            dueOnly: _dueOnly,
                          ),
                        ),
                      );
                      _reloadDecks();
                    },
                  );
                },
              );
            },
          ),
  );
}

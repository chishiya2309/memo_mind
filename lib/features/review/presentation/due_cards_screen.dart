import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/local_due_cards_source.dart';
import '../data/local_review_repository.dart';
import '../domain/due_cards_source.dart';
import '../domain/review_repository.dart';
import 'review_session_screen.dart';

class DueCardsScreen extends StatefulWidget {
  const DueCardsScreen({
    super.key,
    this.source,
    this.reviewRepository,
    required this.onOpenLibrary,
    this.clock,
  });
  final DueCardsSource? source;
  final ReviewRepository? reviewRepository;
  final VoidCallback onOpenLibrary;
  final DateTime Function()? clock;
  @override
  State<DueCardsScreen> createState() => DueCardsScreenState();
}

class DueCardsScreenState extends State<DueCardsScreen>
    with WidgetsBindingObserver {
  late final _source = widget.source ?? LocalDueCardsSource();
  late final _review = widget.reviewRepository ?? LocalReviewRepository();
  late Future<(List<DueCard>, bool)> _data;
  bool _openingReview = false;
  bool get _unsupported =>
      widget.source == null &&
      (kIsWeb || defaultTargetPlatform != TargetPlatform.android);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _data = _load();
    _data.ignore();
  }

  Future<(List<DueCard>, bool)> _load() async {
    if (_unsupported) return (<DueCard>[], false);
    final cards = await _source.getDueCards(
      (widget.clock ?? DateTime.now)().toUtc(),
    );
    return (cards, await _source.hasActiveSession());
  }

  Future<void> reload() async {
    if (!mounted) return;
    final next = _load();
    next.ignore();
    setState(() {
      _data = next;
    });
    try {
      await next;
    } catch (_) {
      /* FutureBuilder renders retry. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) reload();
  }

  Future<void> _startReview() async {
    setState(() => _openingReview = true);
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReviewSessionScreen(repository: _review, dueOnly: true),
        ),
      );
      await reload();
    } finally {
      if (mounted) {
        setState(() => _openingReview = false);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Thẻ đến hạn'),
      actions: [
        IconButton(
          onPressed: reload,
          tooltip: 'Làm mới',
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: _unsupported
        ? const Center(
            child: Text('Danh sách thẻ đến hạn hiện hỗ trợ trên Android.'),
          )
        : FutureBuilder<(List<DueCard>, bool)>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(
                  child: TextButton(
                    onPressed: reload,
                    child: const Text('Không thể tải thẻ đến hạn. Thử lại'),
                  ),
                );
              }
              final (cards, hasSession) = snapshot.data!;
              return Column(
                children: [
                  if (hasSession || cards.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: FilledButton.icon(
                        onPressed: _openingReview ? null : _startReview,
                        icon: const Icon(Icons.play_arrow),
                        label: Text(
                          hasSession
                              ? 'Tiếp tục phiên ôn đang dở'
                              : 'Bắt đầu ôn',
                        ),
                      ),
                    ),
                  Expanded(
                    child: cards.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text('Bạn chưa có thẻ đến hạn'),
                                TextButton(
                                  onPressed: widget.onOpenLibrary,
                                  child: const Text('Về Thư viện'),
                                ),
                              ],
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: reload,
                            child: ListView.builder(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: cards.length,
                              itemBuilder: (context, index) => ListTile(
                                title: Text(
                                  cards[index].card.front,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  '${cards[index].card.type.wireName} • ${cards[index].deckTitle}',
                                ),
                              ),
                            ),
                          ),
                  ),
                ],
              );
            },
          ),
  );
}

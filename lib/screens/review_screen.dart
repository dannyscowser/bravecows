import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../providers/hanzi_provider.dart';
import '../services/db_service.dart';
import '../utils/pinyin.dart';

class ReviewScreen extends StatefulWidget {
  const ReviewScreen({super.key});

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  static const _practiceModeKey = 'practice_mode';
  static const _practiceBatchKey = 'practice_batch_size';
  static const _practiceDueBatchKey = 'practice_due_batch_size';
  static const List<int> _batchOptions = [30, 50, 100, 250, 500, -1];
  static const List<int> _dueBatchOptions = [25, 50, 100];
  bool _showBack = false;
  int? _sessionTotal;
  PracticeMode _mode = PracticeMode.due;
  Character? _lastReviewed;
  bool? _lastWasCorrect;
  int _reviewCount = 0;
  int _correctCount = 0;
  late Future<Map<String, int>> _accuracyFuture;
  int _batchSize = 50;
  int _dueBatchSize = 25;
  bool _loadingPractice = false;
  List<Character> _wrongs = [];
  bool _showStamp = false;
  List<Character> _lastSessionWrongs = [];

  @override
  void initState() {
    super.initState();
    _accuracyFuture = DBService.instance.getAccuracyStats();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initPractice(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Practice')),
      body: Consumer<HanziProvider>(
        builder: (context, provider, _) {
          final queue = _activeQueue(provider);
          if (provider.loadingDue && _mode == PracticeMode.due) {
            return const Center(child: CircularProgressIndicator());
          }
          if (_loadingPractice && _mode != PracticeMode.due) {
            return const Center(child: CircularProgressIndicator());
          }
          if (queue.isEmpty && (_sessionTotal ?? 0) == 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Text(
                    'Nothing to practice. Add characters to study and come back.'),
              ),
            );
          }
          if (queue.isEmpty) {
            _lastSessionWrongs = List<Character>.from(_wrongs);
            return _buildSummary(provider);
          }
          if (_sessionTotal == null || (_sessionTotal ?? 0) < queue.length) {
            _sessionTotal = queue.length;
            _reviewCount = 0;
            _correctCount = 0;
            _lastReviewed = null;
            _lastWasCorrect = null;
            _showBack = false;
          }
          final sessionTotal = _sessionTotal ?? queue.length;
          final card = queue.first;
          final completed = sessionTotal - queue.length;
          if (_showStamp &&
              _lastReviewed != null &&
              _lastReviewed?.traditional != card.traditional) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _showStamp = false);
            });
          }
          final stampVisible =
              _showStamp && _lastReviewed?.traditional == card.traditional;
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Row(
                  children: [
                    DropdownButton<PracticeMode>(
                      value: _mode,
                      onChanged: (v) async {
                        if (v == null) return;
                        await _loadForMode(provider, v);
                      },
                      items: const [
                        DropdownMenuItem(
                          value: PracticeMode.due,
                          child: Text('Due/Ready'),
                        ),
                        DropdownMenuItem(
                          value: PracticeMode.all,
                          child: Text('All in list'),
                        ),
                        DropdownMenuItem(
                          value: PracticeMode.wrongs,
                          child: Text('Wrongs only'),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    if (_mode == PracticeMode.due)
                      DropdownButton<int>(
                        value: _dueBatchSize,
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _dueBatchSize = v);
                          await _loadForMode(provider, _mode);
                        },
                        items: const [
                          DropdownMenuItem(value: 25, child: Text('25')),
                          DropdownMenuItem(value: 50, child: Text('50')),
                          DropdownMenuItem(value: 100, child: Text('100')),
                        ],
                      ),
                    if (_mode != PracticeMode.due)
                      DropdownButton<int>(
                        value: _batchSize,
                        onChanged: (v) async {
                          if (v == null) return;
                          setState(() => _batchSize = v);
                          await _loadForMode(provider, _mode);
                        },
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('30')),
                          DropdownMenuItem(value: 50, child: Text('50')),
                          DropdownMenuItem(value: 100, child: Text('100')),
                          DropdownMenuItem(value: 250, child: Text('250')),
                          DropdownMenuItem(value: 500, child: Text('500')),
                          DropdownMenuItem(value: -1, child: Text('All')),
                        ],
                      ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: _lastReviewed == null
                          ? null
                          : () async {
                              final last = _lastReviewed!;
                              await provider.undoLastReview(last);
                              if (!mounted) return;
                              setState(() {
                                _showBack = false;
                                if (_reviewCount > 0) {
                                  _reviewCount -= 1;
                                  if (_lastWasCorrect == true &&
                                      _correctCount > 0) {
                                    _correctCount -= 1;
                                  }
                                }
                                _lastWasCorrect = null;
                                _lastReviewed = null;
                                _sessionTotal = queue.length;
                              });
                            },
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo'),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('Card ${completed + 1} of $sessionTotal'),
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (sessionTotal == 0) ? 0 : completed / sessionTotal,
                ),
                const SizedBox(height: 8),
                Text(
                  _reviewCount == 0
                      ? 'Accuracy: —'
                      : 'Accuracy: ${(_correctCount / _reviewCount * 100).toStringAsFixed(0)}%',
                ),
                FutureBuilder<Map<String, int>>(
                  future: _accuracyFuture,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const SizedBox(height: 0);
                    final total = snapshot.data?['total'] ?? 0;
                    final correct = snapshot.data?['correct'] ?? 0;
                    final pct = total == 0
                        ? '—'
                        : '${(correct / total * 100).toStringAsFixed(0)}%';
                    return Text('All-time: $pct');
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        provider.skipCard(card, _mode);
                        setState(() {
                          _showBack = false;
                          _showStamp = false;
                        });
                      },
                      icon: const Icon(Icons.skip_next),
                      label: const Text('Skip'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final cardWidth =
                            (constraints.maxWidth * 0.9).clamp(320.0, 560.0);
                        return SizedBox(
                          width: cardWidth,
                          child: GestureDetector(
                            onTap: () => setState(() => _showBack = !_showBack),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                AspectRatio(
                                  aspectRatio: 3 / 4,
                                  child: _FlashCard(
                                    showBack: _showBack,
                                    front: _CardFront(card: card),
                                    back: _CardBack(card: card),
                                  ),
                                ),
                                IgnorePointer(
                                  child: Align(
                                    alignment: Alignment.bottomCenter,
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 24.0),
                                      child: AnimatedScale(
                                        scale: stampVisible ? 0.95 : 1.05,
                                        duration:
                                            const Duration(milliseconds: 240),
                                        child: AnimatedOpacity(
                                          opacity: stampVisible ? 1 : 0,
                                          duration:
                                              const Duration(milliseconds: 240),
                                          child: Image.asset(
                                            'assets/cows_dayin_trans.png',
                                            width: 110,
                                            color: Colors.white.withAlpha(216),
                                            colorBlendMode: BlendMode.modulate,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                if (!_showBack)
                  FilledButton(
                    onPressed: () => setState(() => _showBack = true),
                    child: const Text('Reveal'),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _mark(provider, false, card),
                        icon: const Icon(Icons.close),
                        label: const Text('Wrong'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _mark(provider, true, card),
                        icon: const Icon(Icons.check),
                        label: const Text('Correct'),
                      ),
                      OutlinedButton(
                        onPressed: () => _markKnown(provider, card),
                        child: const Text('Known'),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _initPractice(BuildContext context) async {
    final provider = Provider.of<HanziProvider>(context, listen: false);
    final savedMode = _modeFromStored(
        await DBService.instance.getIntSetting(_practiceModeKey));
    final savedBatch =
        await DBService.instance.getIntSetting(_practiceBatchKey);
    final savedDueBatch =
        await DBService.instance.getIntSetting(_practiceDueBatchKey);
    final restoredBatch =
        (savedBatch != null && _batchOptions.contains(savedBatch))
            ? savedBatch
            : null;
    final restoredDueBatch =
        (savedDueBatch != null && _dueBatchOptions.contains(savedDueBatch))
            ? savedDueBatch
            : null;

    if (!mounted) return;
    setState(() {
      if (savedMode != null) _mode = savedMode;
      if (restoredBatch != null) _batchSize = restoredBatch;
      if (restoredDueBatch != null) _dueBatchSize = restoredDueBatch;
    });
    await _loadForMode(provider, _mode, persist: false);
    // Fallback: if the chosen mode has no cards, try the standard due queue.
    if (_activeQueue(provider).isEmpty && _mode != PracticeMode.due) {
      await _loadForMode(provider, PracticeMode.due);
    }
  }

  Widget _buildSummary(HanziProvider provider) {
    final accuracy = _reviewCount == 0
        ? '—'
        : '${(_correctCount / _reviewCount * 100).toStringAsFixed(0)}%';
    _lastSessionWrongs = List<Character>.from(_wrongs);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Session complete',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Reviewed: $_reviewCount • Accuracy: $accuracy'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (_wrongs.isNotEmpty)
                FilledButton(
                  onPressed: () async {
                    await _loadForMode(provider, PracticeMode.wrongs,
                        seedWrongs: _wrongs);
                  },
                  child: const Text('Replay wrongs'),
                ),
              FilledButton.tonal(
                onPressed: () async {
                  await _loadForMode(provider, PracticeMode.all);
                },
                child: const Text('New shuffled set'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<Character> _activeQueue(HanziProvider provider) {
    return _mode == PracticeMode.due
        ? provider.dueQueue
        : provider.practiceQueue;
  }

  Future<void> _loadForMode(HanziProvider provider, PracticeMode mode,
      {List<Character>? seedWrongs, bool persist = true}) async {
    setState(() {
      _mode = mode;
      _showBack = false;
      _sessionTotal = 0;
      _reviewCount = 0;
      _correctCount = 0;
      _lastReviewed = null;
      _lastWasCorrect = null;
      _wrongs = seedWrongs ?? _lastSessionWrongs;
      _showStamp = false;
      _loadingPractice = mode != PracticeMode.due;
    });
    if (persist) {
      await _persistPracticePrefs();
    }
    try {
      switch (mode) {
        case PracticeMode.due:
          await provider.loadDueQueue(limitUnknown: _dueBatchSize);
          break;
        case PracticeMode.all:
          final limit = _batchSize == -1 ? null : _batchSize;
          await provider.loadPracticeQueueAll(limit: limit);
          break;
        case PracticeMode.wrongs:
          final limit = _batchSize == -1 ? null : _batchSize;
          await provider.loadWrongsAllTime(limit: limit);
          break;
      }
    } finally {
      if (mounted) {
        setState(() {
          _loadingPractice = false;
          _sessionTotal = _activeQueue(provider).length;
        });
      }
    }
  }

  Future<void> _mark(
      HanziProvider provider, bool correct, Character card) async {
    _lastReviewed = card;
    _lastWasCorrect = correct;
    if (!correct) {
      _wrongs.add(card);
    }
    await provider.recordReview(card.traditional, correct,
        listId: provider.defaultListId);
    setState(() {
      _showBack = false;
      _reviewCount += 1;
      if (correct) _correctCount += 1;
      _sessionTotal = _activeQueue(provider).isEmpty
          ? _sessionTotal
          : (_sessionTotal ?? _activeQueue(provider).length);
      _accuracyFuture = DBService.instance.getAccuracyStats();
    });
  }

  Future<void> _markKnown(HanziProvider provider, Character card) async {
    setState(() {
      _showStamp = true;
      _lastReviewed = card;
    });
    await Future.delayed(const Duration(milliseconds: 300));
    await provider.markKnown(card.traditional);
    if (!mounted) return;
    setState(() {
      _showBack = false;
      _lastWasCorrect = true;
      _reviewCount += 1;
      _correctCount += 1;
      _accuracyFuture = DBService.instance.getAccuracyStats();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted && _lastReviewed?.traditional == card.traditional) {
        setState(() => _showStamp = false);
      }
    });
  }

  Future<void> _persistPracticePrefs() async {
    await DBService.instance
        .setSetting(_practiceModeKey, '${_modeToStored(_mode)}');
    await DBService.instance.setSetting(_practiceBatchKey, '$_batchSize');
    await DBService.instance.setSetting(_practiceDueBatchKey, '$_dueBatchSize');
  }

  PracticeMode? _modeFromStored(int? raw) {
    switch (raw) {
      case 0:
        return PracticeMode.due;
      case 1:
        return PracticeMode.all;
      case 2:
        return PracticeMode.wrongs;
    }
    return null;
  }

  int _modeToStored(PracticeMode mode) {
    switch (mode) {
      case PracticeMode.due:
        return 0;
      case PracticeMode.all:
        return 1;
      case PracticeMode.wrongs:
        return 2;
    }
  }
}

class _FlashCard extends StatelessWidget {
  final bool showBack;
  final Widget front;
  final Widget back;

  const _FlashCard(
      {required this.showBack, required this.front, required this.back});

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) {
        final rotate = Tween(begin: pi, end: 0.0).animate(animation);
        return AnimatedBuilder(
          animation: rotate,
          child: child,
          builder: (context, child) {
            final isUnder = (child!.key != ValueKey(showBack));
            final value = isUnder ? min(rotate.value, pi / 2) : rotate.value;
            return Transform(
              transform: Matrix4.rotationY(value),
              alignment: Alignment.center,
              child: child,
            );
          },
        );
      },
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: Alignment.center,
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: showBack
          ? Container(
              key: const ValueKey(true),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.all(20),
              child: back,
            )
          : Container(
              key: const ValueKey(false),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant),
              ),
              padding: const EdgeInsets.all(20),
              child: front,
            ),
    );
  }
}

class _CardFront extends StatelessWidget {
  final Character card;
  const _CardFront({required this.card});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HanziProvider>(context, listen: false);
    final primary = provider.displayHanzi(card);
    final hasAlt = card.simplified != card.traditional;
    final alt =
        primary == card.traditional ? card.simplified : card.traditional;
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.center,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (card.isKnown != null) ...[
              Chip(
                label: Text(card.isKnown == true ? 'Known' : 'Learning'),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              primary,
              style: Theme.of(context)
                  .textTheme
                  .displayLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            if (hasAlt) ...[
              const SizedBox(height: 8),
              Text(
                alt,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ],
            const SizedBox(height: 12),
            const Text('Tap to flip'),
          ],
        ),
      ),
    );
  }
}

class _CardBack extends StatelessWidget {
  final Character card;
  const _CardBack({required this.card});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HanziProvider>(context, listen: false);
    final primary = provider.displayHanzi(card);
    final hasAlt = card.simplified != card.traditional;
    final alt =
        primary == card.traditional ? card.simplified : card.traditional;
    final stackChildren = <Widget>[];
    stackChildren.add(
      Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SizedBox(
              height: constraints.maxHeight,
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 8.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      primary,
                      style: Theme.of(context)
                          .textTheme
                          .displayLarge
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    if (hasAlt) ...[
                      const SizedBox(height: 6),
                      Text(
                        alt,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      formatPinyin(card.pinyin),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      card.definitions,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
    if (card.isKnown == true) {
      stackChildren.add(
        Positioned(
          right: 12,
          bottom: 12,
          child: Opacity(
            opacity: 0.15,
            child: Image.asset(
              'assets/cows_dayin_trans.png',
              width: 84,
              color: Colors.white,
              colorBlendMode: BlendMode.modulate,
            ),
          ),
        ),
      );
    }

    return Stack(children: stackChildren);
  }
}

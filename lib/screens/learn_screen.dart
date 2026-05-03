import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../providers/hanzi_provider.dart';
import '../models/study_list.dart';
import '../utils/pinyin.dart';
import '../services/db_service.dart';
import '../widgets/cow_loader.dart';

class LearnScreen extends StatefulWidget {
  const LearnScreen({super.key});

  @override
  State<LearnScreen> createState() => _LearnScreenState();
}

class _LearnScreenState extends State<LearnScreen> {
  late Future<List<Character>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Character>> _load() {
    final provider = Provider.of<HanziProvider>(context, listen: false);
    return provider.loadLearnBatch(
        total: 25, maxKnown: 5, seed: DateTime.now().microsecondsSinceEpoch);
  }

  Future<void> _refresh() async {
    final next = _load();
    setState(() {
      _future = next;
    });
    await next;
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HanziProvider>(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Learn new characters'),
        actions: [
          IconButton(
            tooltip: 'New batch',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: FutureBuilder<List<Character>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CowLoader());
          }
          if (snapshot.hasError) {
            return Center(
              child: Text('Failed to load: ${snapshot.error}'),
            );
          }
          final items = snapshot.data ?? [];
          final deduped = _dedup(items);
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'You have added all high-frequency characters. Remove some from study to learn again.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '25-character batch, weighted to common entries. Up to 5 familiar characters can appear.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap a card to add it to your General list.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    itemCount: deduped.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final ch = deduped[index];
                      final display = provider.displayHanzi(ch);
                      return ListTile(
                        title: Text(
                          '$display ${ch.simplified != ch.traditional ? "(${ch.traditional == display ? ch.simplified : ch.traditional})" : ""} • ${formatPinyin(ch.pinyin)}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        subtitle: Text(
                          ch.definitions,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: ElevatedButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Add'),
                          onPressed: () async {
                            final target = provider.defaultListId ??
                                await DBService.instance.defaultListId();
                            if (!context.mounted) return;
                            final listName = provider.lists
                                .firstWhere(
                                    (l) => l.id == target,
                                    orElse: () =>
                                        const StudyList(id: 0, name: 'General'))
                                .name;
                            await provider.addToList(ch.traditional, target);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(SnackBar(
                                  duration: const Duration(milliseconds: 900),
                                  content: Text(
                                      'Added ${ch.traditional} to $listName')));
                            setState(() {
                              items.removeWhere(
                                  (c) => c.traditional == ch.traditional);
                            });
                          },
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Character> _dedup(List<Character> items) {
    final seen = <String>{};
    final result = <Character>[];
    for (final c in items) {
      if (seen.add(c.traditional)) {
        result.add(c);
      }
    }
    return result;
  }
}

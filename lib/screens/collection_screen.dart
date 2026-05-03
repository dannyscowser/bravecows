import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../providers/hanzi_provider.dart';
import '../services/db_service.dart';
import '../utils/pinyin.dart';
import '../widgets/cow_loader.dart';
import 'character_detail_screen.dart';

class CollectionScreen extends StatefulWidget {
  const CollectionScreen({super.key});

  @override
  State<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends State<CollectionScreen> {
  late Future<_CollectionData> _future;
  bool _hideListed = false;

  @override
  void initState() {
    super.initState();
    _future = _load(limit: 200);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HanziProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Full Character List')),
      body: FutureBuilder<_CollectionData>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CowLoader());
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('Failed to load: ${snapshot.error}'),
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: _reload,
                      child: const Text('Retry'),
                    )
                  ],
                ),
              ),
            );
          }
          final data = snapshot.data!;
          final filtered = _applyFilters(data.items, provider, data.listed);
          if (filtered.isEmpty) {
            return const Center(child: Text('No characters found.'));
          }
          return RefreshIndicator(
            onRefresh: _reload,
            child: Column(
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilterChip(
                        label: const Text('Hide if in a list'),
                        selected: _hideListed,
                        onSelected: (v) => setState(() => _hideListed = v),
                      ),
                      SegmentedButton<DisplayScript>(
                        segments: const [
                          ButtonSegment(
                              value: DisplayScript.traditional,
                              label: Text('Traditional')),
                          ButtonSegment(
                              value: DisplayScript.simplified,
                              label: Text('Simplified')),
                        ],
                        selected: {provider.displayScript},
                        showSelectedIcon: false,
                        onSelectionChanged: (vals) {
                          if (vals.isEmpty) return;
                          provider.setDisplayScript(vals.first);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: filtered.length + 1,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return TextButton(
                          onPressed: () async {
                            setState(() {
                              _future = _load(limit: filtered.length + 200);
                            });
                          },
                          child: const Text('Load more'),
                        );
                      }
                      final ch = filtered[index];
                      final display = provider.displayHanzi(ch);
                      final inActiveList =
                          provider.studySet.contains(ch.traditional);
                      final inAnyList = data.listed.contains(ch.traditional);
                      return ListTile(
                        title: Text(
                            '$display ${ch.simplified != ch.traditional ? "(${ch.traditional == display ? ch.simplified : ch.traditional})" : ""} • ${formatPinyin(ch.pinyin)}'),
                        subtitle: Text(
                          ch.definitions,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: inAnyList
                            ? Icon(
                                inActiveList
                                    ? Icons.check_circle
                                    : Icons.check_circle_outline,
                                color: inActiveList
                                    ? Colors.green
                                    : Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                              )
                            : const Icon(Icons.circle_outlined),
                        onTap: () => _openCharacter(context, ch),
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

  Future<void> _reload() async {
    setState(() {
      _future = _load(limit: 200);
    });
    await _future;
  }

  Future<_CollectionData> _load({int limit = 200}) async {
    final items = await DBService.instance.getCollection(limit: limit);
    final listed = await DBService.instance.getAllListItems();
    return _CollectionData(items: items, listed: listed);
  }

  void _openCharacter(BuildContext context, Character ch) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CharacterDetailScreen(
          traditional: ch.traditional,
          initialCharacter: ch,
        ),
      ),
    );
  }

  List<Character> _applyFilters(
      List<Character> items, HanziProvider provider, Set<String> listed) {
    final filtered = items.where((c) {
      if (_hideListed && listed.contains(c.traditional)) {
        return false;
      }
      return true;
    }).toList();
    return filtered;
  }
}

class _CollectionData {
  final List<Character> items;
  final Set<String> listed;
  _CollectionData({required this.items, required this.listed});
}

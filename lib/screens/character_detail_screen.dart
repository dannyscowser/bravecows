import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../providers/hanzi_provider.dart';
import '../services/db_service.dart';
import '../utils/pinyin.dart';

class CharacterDetailScreen extends StatefulWidget {
  final String traditional;
  final Character? initialCharacter;
  const CharacterDetailScreen(
      {super.key, required this.traditional, this.initialCharacter});

  @override
  State<CharacterDetailScreen> createState() => _CharacterDetailScreenState();
}

class _CharacterDetailScreenState extends State<CharacterDetailScreen> {
  late Future<Character?> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadCharacter();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HanziProvider>(context);
    final inStudy = provider.studySet.contains(widget.traditional);
    return Scaffold(
      appBar: AppBar(title: Text(widget.traditional)),
      body: FutureBuilder<Character?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
                child: Text('Failed to load character: ${snapshot.error}'));
          }
          final ch = snapshot.data;
          if (ch == null) {
            return const Center(child: Text('Character not found.'));
          }
          final display = provider.displayHanzi(ch);
          final defs = ch.definitions
              .split('/')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          return Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Column(
                    children: [
                      Text(
                        display,
                        style: Theme.of(context)
                            .textTheme
                            .displayMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      if (ch.simplified != ch.traditional)
                        Text(
                          provider.displayScript == DisplayScript.traditional
                              ? 'Simplified: ${ch.simplified}'
                              : 'Traditional: ${ch.traditional}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Pinyin: ${formatPinyin(ch.pinyin)}',
                            style: Theme.of(context).textTheme.titleMedium),
                        if (ch.frequency != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 6.0),
                            child: Text(
                                'Frequency: ${ch.frequency!.toStringAsFixed(0)}',
                                style: Theme.of(context).textTheme.bodySmall),
                          ),
                        const SizedBox(height: 12),
                        Text('Definitions',
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        ...defs.map((d) => Padding(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 2.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• '),
                                  Expanded(child: Text(d)),
                                ],
                              ),
                            )),
                        if (defs.isEmpty) Text(ch.definitions),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                FutureBuilder<bool>(
                  future: provider.isKnown(ch.traditional),
                  builder: (context, knownSnap) {
                    final known = knownSnap.data == true;
                    return Chip(
                      label: Text(known ? 'Known' : 'Learning'),
                      backgroundColor: known
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.secondaryContainer,
                      labelStyle: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer),
                    );
                  },
                ),
                const Spacer(),
                Row(
                  children: [
                    Expanded(
                      child: inStudy
                          ? OutlinedButton.icon(
                              onPressed: () async {
                                await provider.removeFromStudy(ch.traditional);
                                if (!mounted) return;
                                setState(() {});
                              },
                              icon: const Icon(Icons.remove_circle_outline),
                              label: const Text('Remove from Study'),
                            )
                          : FilledButton.icon(
                              onPressed: () async {
                                await _pickListAndAdd(context, provider, ch);
                                if (!mounted) return;
                                setState(() {});
                              },
                              icon: const Icon(Icons.add_circle_outline),
                              label: const Text('Add to Study'),
                            ),
                    ),
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }

  Future<Character?> _loadCharacter() async {
    final seed = widget.initialCharacter;
    try {
      final fetched = await DBService.instance.getCharacter(widget.traditional);
      return fetched ?? seed;
    } catch (e) {
      if (seed != null) return seed;
      rethrow;
    }
  }

  Future<void> _pickListAndAdd(
      BuildContext context, HanziProvider provider, Character ch) async {
    final lists = provider.lists;
    int? selectedId = provider.defaultListId;
    final controller = TextEditingController();
    await showModalBottomSheet(
      context: context,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Add "${ch.traditional}" to list',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              // ignore: deprecated_member_use
              ...lists.map((l) => RadioListTile<int>(
                    value: l.id,
                    // ignore: deprecated_member_use
                    groupValue: selectedId,
                    // ignore: deprecated_member_use
                    onChanged: (v) => setState(() => selectedId = v),
                    title: Text('${l.emoji ?? ""} ${l.name}'),
                  )),
              const Divider(),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                    labelText: 'New list name (optional)'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Add'),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
    if (controller.text.trim().isNotEmpty) {
      selectedId =
          await provider.createList(controller.text.trim(), emoji: '🆕');
    }
    final targetId = selectedId ?? provider.defaultListId;
    if (targetId != null) {
      await provider.addToList(ch.traditional, targetId);
    }
  }
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/character.dart';
import '../providers/hanzi_provider.dart';
import '../services/db_service.dart';
import '../widgets/cow_loader.dart';
import '../utils/pinyin.dart';
import 'character_detail_screen.dart';

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  List<Character> _results = [];
  bool _searching = false;
  String _lastQuery = '';
  Timer? _debounce;
  int _queryVersion = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () async {
      final current = ++_queryVersion;
      setState(() {
        _searching = true;
        _lastQuery = q.trim();
      });
      try {
        final items = await DBService.instance.search(q.trim());
        if (!mounted || current != _queryVersion) return;
        setState(() {
          _results = items;
        });
      } catch (e) {
        if (!mounted || current != _queryVersion) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Search failed: $e')),
        );
      } finally {
        if (mounted && current == _queryVersion) {
          setState(() => _searching = false);
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<HanziProvider>(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Search')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              decoration: InputDecoration(
                labelText: 'Hanzi or pinyin',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () => _doSearch(_controller.text),
                ),
              ),
              textInputAction: TextInputAction.search,
              enableSuggestions: true,
              autocorrect: false,
              onSubmitted: _doSearch,
            ),
            const SizedBox(height: 12),
            if (_searching) const CowLoader(),
            Expanded(
              child: _searching
                  ? const SizedBox.shrink()
                  : _results.isEmpty && _lastQuery.isNotEmpty
                      ? const Center(child: Text('No results yet.'))
                      : ListView.builder(
                          itemCount: _results.length,
                          itemBuilder: (context, index) {
                            final ch = _results[index];
                            final display = provider.displayHanzi(ch);
                            final inStudy =
                                provider.studySet.contains(ch.traditional);
                            return ListTile(
                              title: Text(
                                  '$display ${ch.simplified != ch.traditional ? "(${ch.traditional == display ? ch.simplified : ch.traditional})" : ""} • ${formatPinyin(ch.pinyin)}'),
                              subtitle: Text(
                                ch.definitions,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  inStudy
                                      ? Icons.remove_circle_outline
                                      : Icons.add_circle_outline,
                                  color: inStudy ? Colors.red : null,
                                ),
                                onPressed: () async {
                                  if (inStudy) {
                                    await provider.removeFromStudy(ch.traditional);
                                  } else {
                                    await _pickListAndAdd(context, provider, ch,
                                        primaryMeaning:
                                            ch.definitions.split('/').first);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                        ..hideCurrentSnackBar()
                                        ..showSnackBar(const SnackBar(
                                            content:
                                                Text('Added to active list'),
                                            duration:
                                                Duration(milliseconds: 900)));
                                    }
                                  }
                                  if (mounted) setState(() {});
                                },
                              ),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => CharacterDetailScreen(
                                    traditional: ch.traditional,
                                    initialCharacter: ch,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _pickListAndAdd(
      BuildContext context, HanziProvider provider, Character ch,
      {String? primaryMeaning}) async {
    final lists = provider.lists;
    int? selectedId = provider.defaultListId;
    final controller = TextEditingController();
    final newListName = ValueNotifier<String>('');
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
                    onChanged: (v) {
                      // ignore: deprecated_member_use
                      Navigator.pop(context);
                      // ignore: deprecated_member_use
                      setState(() => selectedId = v);
                    },
                    title: Text('${l.emoji ?? ""} ${l.name}'),
                  )),
              const Divider(),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                    labelText: 'New list name (optional)'),
                onChanged: (v) => newListName.value = v.trim(),
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
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    child: const Text('Add'),
                  ),
                ],
              )
            ],
          ),
        );
      },
    );
    // Create new list if provided
    if (controller.text.trim().isNotEmpty) {
      selectedId =
          await provider.createList(controller.text.trim(), emoji: '🆕');
    }
    final targetId = selectedId ?? provider.defaultListId;
    if (targetId != null) {
      await provider.addToList(ch.traditional, targetId,
          meaning: primaryMeaning);
    }
  }
}

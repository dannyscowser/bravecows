import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/study_list.dart';
import '../providers/hanzi_provider.dart';
import '../services/db_service.dart';

class ListsScreen extends StatefulWidget {
  const ListsScreen({super.key});

  @override
  State<ListsScreen> createState() => _ListsScreenState();
}

class _ListsScreenState extends State<ListsScreen> {
  final Map<int, Future<Map<String, int>>> _statsCache = {};

  Future<Map<String, int>> _statsFor(StudyList list) {
    return _statsCache[list.id] ??= DBService.instance.getListStats(list.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lists')),
      body: Consumer<HanziProvider>(
        builder: (context, provider, _) {
          final lists = provider.lists;
          if (lists.isEmpty) {
            return const Center(child: Text('No lists yet.'));
          }
          return ListView.separated(
            itemCount: lists.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final l = lists[index];
              return FutureBuilder<Map<String, int>>(
                future: _statsFor(l),
                builder: (context, snapshot) {
                  final stats = snapshot.data;
                  final known = stats?['known'] ?? 0;
                  final unknown = stats?['unknown'] ?? 0;
                  final active = provider.defaultListId == l.id;
                  return ListTile(
                    title: Text('${l.emoji ?? ""} ${l.name}'),
                    subtitle: Text(
                        '$known known / $unknown unknown${l.isSystem ? "" : ""}'),
                    trailing: active ? const Chip(label: Text('Active')) : null,
                    onTap: () async {
                      await provider.setActiveList(l.id);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Active list set to ${l.name}')));
                      }
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}

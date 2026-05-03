import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/hanzi_provider.dart';
import '../models/study_list.dart';
import 'collection_screen.dart';
import 'licenses_screen.dart';
import 'learn_screen.dart';
import 'lists_screen.dart';
import 'review_screen.dart';
import 'search_screen.dart';
import 'zidex_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const bool _showCollection = true; // toggle visibility if desired

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Brave Cows'),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Image.asset('assets/cows_dayin.png'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SearchScreen()),
            ),
            tooltip: 'Search',
          ),
          Consumer<HanziProvider>(
            builder: (context, provider, _) {
              return PopupMenuButton<String>(
                icon: const Icon(Icons.list),
                tooltip: 'Study list',
                itemBuilder: (context) => [
                  ...provider.lists.map(
                    (l) => PopupMenuItem(
                      value: 'list_${l.id}',
                      child: Row(
                        children: [
                          if (provider.defaultListId == l.id)
                            const Icon(Icons.check, size: 16),
                          if (provider.defaultListId == l.id)
                            const SizedBox(width: 6),
                          Text('${l.emoji ?? ""} ${l.name}'),
                        ],
                      ),
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'new',
                    child: Text('New list...'),
                  ),
                ],
                onSelected: (v) async {
                  if (v == 'new') {
                    final name = await _promptNewList(context);
                    if (name != null && name.trim().isNotEmpty) {
                      if (!context.mounted) return;
                      final id = await Provider.of<HanziProvider>(context,
                              listen: false)
                          .createList(name.trim(), emoji: '🆕');
                      if (!context.mounted) return;
                      await Provider.of<HanziProvider>(context, listen: false)
                          .setActiveList(id);
                    }
                  } else if (v.startsWith('list_')) {
                    final id = int.tryParse(v.split('_').last);
                    if (id != null) {
                      if (!context.mounted) return;
                      await Provider.of<HanziProvider>(context, listen: false)
                          .setActiveList(id);
                    }
                  }
                },
              );
            },
          ),
          Consumer<HanziProvider>(
            builder: (context, provider, _) {
              return PopupMenuButton<DisplayScript>(
                icon: const Icon(Icons.translate),
                tooltip: 'Script',
                initialValue: provider.displayScript,
                onSelected: (val) => provider.setDisplayScript(val),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: DisplayScript.traditional,
                    child: Text('Traditional'),
                  ),
                  PopupMenuItem(
                    value: DisplayScript.simplified,
                    child: Text('Simplified'),
                  ),
                ],
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LicensesScreen()),
            ),
            tooltip: 'Data Sources & Licenses',
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<HanziProvider>(
          builder: (context, provider, _) {
            final dueCount = provider.dueCount;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Today\'s practice',
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Consumer<HanziProvider>(builder: (context, p, _) {
                    final active = p.lists.firstWhere(
                        (l) => l.id == p.defaultListId,
                        orElse: () => p.lists.isNotEmpty
                            ? p.lists.first
                            : StudyList(id: 0, name: 'General', emoji: '🫡'));
                    return Text(
                      'List: ${active.emoji ?? ""} ${active.name}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Text(
                          '$dueCount',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Text('characters to study in this batch'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Practice now'),
                    onPressed: () async {
                      await Provider.of<HanziProvider>(context, listen: false)
                          .loadDueQueue();
                      if (!context.mounted) return;
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const ReviewScreen()),
                      );
                    },
                  ),
                  if (dueCount == 0)
                    const Padding(
                      padding: EdgeInsets.only(top: 8.0),
                      child: Text(
                          'No characters ready. Add characters to learn from Search or Character List.'),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.school),
                    label: const Text('Learn new characters'),
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LearnScreen()),
                    ),
                  ),
                  const SizedBox(height: 32),
                  Text('Learn some of that good good chinese', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 12),
                  ListTile(
                    title: const Text('Search'),
                    subtitle: const Text('Find by character or pinyin, add to study'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SearchScreen()),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Lists & stats'),
                    subtitle: const Text(
                        'View lists, switch active, see counts/progress'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ListsScreen()),
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    title: const Text('Zi-Dex'),
                    subtitle: const Text(
                        'See known characters and progress by frequency'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ZiDexScreen()),
                    ),
                  ),
                  if (_showCollection) ...[
                    const Divider(),
                    ListTile(
                      title: const Text('Full Character List'),
                      subtitle: const Text(
                          'Browse and add by frequency with quick filters'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const CollectionScreen()),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Future<String?> _promptNewList(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New list'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'List name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );
  }
}

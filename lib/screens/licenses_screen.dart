import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class LicensesScreen extends StatelessWidget {
  const LicensesScreen({super.key});

  Future<String> _loadAsset(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (e) {
      return 'License file not found: $path';
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      {'title': 'CC-CEDICT', 'asset': 'assets/licenses/cc_cedict.txt'},
      {'title': 'SUBTLEX-CH', 'asset': 'assets/licenses/subtlex_ch.txt'},
      {'title': 'Tatoeba (sentences)', 'asset': 'assets/licenses/tatoeba.txt'},
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('Data Sources & Licenses')),
      body: ListView.builder(
        itemCount: items.length,
        itemBuilder: (context, index) {
          final it = items[index];
          return ExpansionTile(
            title: Text(it['title'] as String),
            children: [
              FutureBuilder<String>(
                future: _loadAsset(it['asset'] as String),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return Container(
                    width: double.infinity,
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    padding: const EdgeInsets.all(12),
                    child: Text(snapshot.data ?? 'No content'),
                  );
                },
              )
            ],
          );
        },
      ),
    );
  }
}

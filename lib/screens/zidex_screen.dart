import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/hanzi_provider.dart';
import '../services/db_service.dart';

class ZiDexScreen extends StatefulWidget {
  const ZiDexScreen({super.key});

  @override
  State<ZiDexScreen> createState() => _ZiDexScreenState();
}

class _ZiDexScreenState extends State<ZiDexScreen> {
  static const _thresholds = [1000, 2000, 3000, 5000];
  late Future<Map<int, int>> _countsFuture;

  @override
  void initState() {
    super.initState();
    _countsFuture =
        DBService.instance.getKnownCountsByThresholds(_thresholds);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HanziProvider>(context, listen: false)
          .loadKnownCharacters()
          .then((_) {
        if (mounted) {
          setState(() {
            _countsFuture =
                DBService.instance.getKnownCountsByThresholds(_thresholds);
          });
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zi-Dex')),
      body: Consumer<HanziProvider>(
        builder: (context, provider, _) {
          final known = provider.knownCharacters;
          if (known.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                    'No known characters yet. Review more cards to fill your Zi-Dex.'),
              ),
            );
          }
          return Column(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: FutureBuilder<Map<int, int>>(
                  future: _countsFuture,
                  builder: (context, snapshot) {
                    final counts = snapshot.data;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: _thresholds
                          .map(
                            (t) => Chip(
                              label: Text(
                                  'Top $t: ${counts != null ? counts[t] ?? 0 : "…"}${counts != null ? "/$t" : ""}'),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ),
              const Divider(),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 6,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                  ),
                  itemCount: known.length,
                  itemBuilder: (context, index) {
                    final ch = known[index];
                    final display = provider.displayHanzi(ch);
                    return Card(
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            display,
                            style: Theme.of(context)
                                .textTheme
                                .headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

}

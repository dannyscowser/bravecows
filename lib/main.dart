import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'providers/hanzi_provider.dart';
import 'screens/home_screen.dart';
import 'services/db_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DBService.instance.init();
  runApp(const BraveCowsApp());
}

class BraveCowsApp extends StatelessWidget {
  const BraveCowsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => HanziProvider()..load(),
      child: MaterialApp(
        title: 'Brave Cows',
        theme: ThemeData(
          colorSchemeSeed: Colors.green,
          brightness: Brightness.dark,
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}

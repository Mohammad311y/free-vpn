import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FreeVpnApp());
}

class FreeVpnApp extends StatelessWidget {
  const FreeVpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return DynamicColorBuilder(builder: (light, dark) {
      final scheme = dark ??
          ColorScheme.fromSeed(
              seedColor: const Color(0xFF7C4DFF), brightness: Brightness.dark);
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'FreeVPN',
        theme: ThemeData(useMaterial3: true, colorScheme: scheme),
        builder: (c, child) =>
            Directionality(textDirection: TextDirection.rtl, child: child!),
        home: const HomePage(),
      );
    });
  }
}

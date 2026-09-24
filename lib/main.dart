import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'screens/pure_nav_screen.dart';
import 'services/idr_pipeline.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => IdrPipeline()),
      ],
      child: const IdrNavigatorApp(),
    ),
  );
}

class IdrNavigatorApp extends StatelessWidget {
  const IdrNavigatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IDR Navigator - SIH 2026',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF030712),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF0F172A),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0F172A),
          elevation: 0,
        ),
      ),
      home: const PureNavScreen(),
    );
  }
}

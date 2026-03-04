// lib/main.dart
// ✅ COMPLETE FIXED VERSION

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'injection_container.dart' as di;
import 'presentation/pages/home_page.dart';
import 'core/constants/app_constants.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load .env file
  try {
    await dotenv.load(fileName: ".env");
    print("✅ .env file loaded successfully");

    // Test if API key is available
    final apiKey = AppConstants.geminiApiKey;
    print(
      "✅ API key loaded: ${apiKey.substring(0, 5)}...${apiKey.substring(apiKey.length - 5)}",
    );
  } catch (e) {
    print("❌ Error loading .env: $e");
  }

  // ✅ Initialize dependency injection
  try {
    await di.init();
    print("✅ Dependency injection initialized");
  } catch (e) {
    print("❌ Error initializing DI: $e");
    rethrow;
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FL AI Assistant',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.deepPurple, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

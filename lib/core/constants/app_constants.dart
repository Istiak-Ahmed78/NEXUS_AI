import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConstants {
  static String get appName => dotenv.env['APP_NAME'] ?? 'FL AI Assistant';

  static String get geminiApiKey {
    final key = dotenv.env['GEMINI_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception('GEMINI_API_KEY not found in .env file');
    }
    return key;
  }

  // ── OpenWeather API Key ───────────────────────
  static String get openWeatherApiKey {
    final key = dotenv.env['OPENWEATHER_API_KEY'] ?? '';
    if (key.isEmpty) {
      throw Exception(
        '❌ OPENWEATHER_API_KEY is missing in .env file.\n'
        '   Add: OPENWEATHER_API_KEY=your_key_here',
      );
    }
    return key;
  }

  // ✅ Serper API Key (Google Search) ────────────
  static String get serperApiKey {
    final key = dotenv.env['SERPER_API_KEY'];
    if (key == null || key.isEmpty) {
      throw Exception(
        '❌ SERPER_API_KEY is missing in .env file.\n'
        '   Add: SERPER_API_KEY=your_key_here\n'
        '   Get it from: https://serper.dev',
      );
    }
    print('✅ [AppConstants] Serper API Key loaded: ${key.substring(0, 10)}...');
    return key;
  }

  // Speech settings
  static const double speechRate = 0.5;
  static const double pitch = 1.0;
  static const Duration listenDuration = Duration(seconds: 30);
  static const Duration pauseDuration = Duration(seconds: 3);

  // UI Constants
  static const double micButtonSize = 80;
  static const double animationDuration = 1500;
}

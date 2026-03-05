// lib/core/tools/tool_registry.dart

import 'package:google_generative_ai/google_generative_ai.dart';

class ToolRegistry {
  static List<Tool> getTools() {
    return [
      Tool(
        functionDeclarations: [
          // ── 🌤️ WEATHER ──────────────────────────────
          FunctionDeclaration(
            'get_weather',
            'Get current temperature and weather condition at a location',
            Schema(
              SchemaType.object,
              properties: {
                'location': Schema(
                  SchemaType.string,
                  description: 'City name, e.g. Dhaka, London',
                ),
              },
              requiredProperties: ['location'],
            ),
          ),

          // ── ⏰ ALARM ─────────────────────────────────
          FunctionDeclaration(
            'set_alarm',
            'Set an alarm or reminder at a specific time',
            Schema(
              SchemaType.object,
              properties: {
                'time': Schema(
                  SchemaType.string,
                  description: 'Time in HH:MM 24-hour format e.g. 14:00',
                ),
                'label': Schema(
                  SchemaType.string,
                  description: 'Alarm label or title',
                ),
              },
              requiredProperties: ['time', 'label'],
            ),
          ),

          // ── 📞 CALL BY CONTACT NAME ──────────────────
          FunctionDeclaration(
            'make_call',
            'Make a phone call to a saved contact by their name',
            Schema(
              SchemaType.object,
              properties: {
                'contact_name': Schema(
                  SchemaType.string,
                  description: 'Full or partial name of the contact',
                ),
              },
              requiredProperties: ['contact_name'],
            ),
          ),

          // ── 📞 CALL BY PHONE NUMBER ──────────────────  ✅ NEW
          FunctionDeclaration(
            'phone_call',
            'Make a phone call to a specific phone number directly (not from contacts)',
            Schema(
              SchemaType.object,
              properties: {
                'phone_number': Schema(
                  SchemaType.string,
                  description:
                      'Phone number to call, e.g. +8801712345678 or 555-1234',
                ),
              },
              requiredProperties: ['phone_number'],
            ),
          ),

          // ── 🔦 FLASHLIGHT ────────────────────────────
          FunctionDeclaration(
            'toggle_flashlight',
            'Turn the device flashlight on or off',
            Schema(
              SchemaType.object,
              properties: {
                'state': Schema(SchemaType.string, description: 'on or off'),
              },
              requiredProperties: ['state'],
            ),
          ),

          // ── 🌐 WEB SEARCH ────────────────────────────
          FunctionDeclaration(
            'open_web_search',
            'Open a web search for a given query in the browser',
            Schema(
              SchemaType.object,
              properties: {
                'query': Schema(
                  SchemaType.string,
                  description: 'The search query string',
                ),
              },
              requiredProperties: ['query'],
            ),
          ),
        ],
      ),
    ];
  }
}

import 'package:google_generative_ai/google_generative_ai.dart';

class ToolRegistry {
  static List<Tool> getTools() {
    return [
      Tool(
        functionDeclarations: [
          // ── 🔎 SEARCH WEB (PRIMARY - INSTANT RETURN) ────  ✅ MOVED TO TOP
          FunctionDeclaration(
            'search_web',
            'Search the web for information and return results instantly to answer questions. Use this to find current information, news, tips, tutorials, and any web content. Results are returned directly to provide answers.',
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

          // ── 📞 CALL BY PHONE NUMBER ──────────────────
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

          // ── 🕐 TIME ──────────────────────────────────
          FunctionDeclaration(
            'get_time',
            'Get the current time in 12-hour and 24-hour format with timezone',
            Schema(SchemaType.object, properties: {}, requiredProperties: []),
          ),

          // ── 📅 DATE ──────────────────────────────────
          FunctionDeclaration(
            'get_date',
            'Get the current date with day of week, month, and year',
            Schema(SchemaType.object, properties: {}, requiredProperties: []),
          ),

          // ── 🌐 WEB SEARCH (BROWSER) ──────────────────  ⚠️ DEPRIORITIZED
          // Only use this if user explicitly asks to "open browser" or "search in browser"
          FunctionDeclaration(
            'open_web_search',
            'Open a web search in the browser application. Only use this if the user explicitly asks to open a browser or search in a browser. For getting search results to answer questions, use search_web instead.',
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

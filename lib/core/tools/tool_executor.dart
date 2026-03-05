// lib/core/tools/tool_executor.dart

import 'dart:convert';
import 'package:fl_ai/core/constants/app_constants.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:torch_light/torch_light.dart';
import 'package:url_launcher/url_launcher.dart';

class ToolExecutor {
  static final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
      onDidReceiveNotificationResponse: (response) {},
    );
  }

  static Future<Map<String, dynamic>> execute(
    String toolName,
    Map<String, dynamic> args,
  ) async {
    switch (toolName) {
      case 'get_weather':
        return await _getWeather(args['location'] as String);

      case 'set_alarm':
        return await _setAlarm(
          args['time'] as String,
          args['label'] as String? ?? 'Alarm',
        );

      case 'make_call':
        return await _makeCall(args['contact_name'] as String);

      case 'phone_call':
        return await _phoneCall(args['phone_number'] as String);

      case 'toggle_flashlight':
        return await _toggleFlashlight(args['state'] as String);

      case 'open_web_search':
        return await _openWebSearch(args['query'] as String);

      case 'get_time':
        return _getTime();

      case 'get_date':
        return _getDate();

      default:
        return {'success': false, 'error': 'Unknown tool: $toolName'};
    }
  }

  static Future<Map<String, dynamic>> _getWeather(String location) async {
    try {
      final apiKey = AppConstants.openWeatherApiKey;
      final url =
          'https://api.openweathermap.org/data/2.5/weather'
          '?q=$location&appid=$apiKey&units=metric';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'location': data['name'],
          'temperature': data['main']['temp'],
          'feels_like': data['main']['feels_like'],
          'condition': data['weather'][0]['description'],
          'humidity': data['main']['humidity'],
        };
      } else {
        return {'success': false, 'error': 'Weather API error'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _setAlarm(
    String time,
    String label,
  ) async {
    try {
      await Permission.notification.request();

      final parts = time.split(':');
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);

      final now = DateTime.now();
      var alarmTime = DateTime(now.year, now.month, now.day, hour, minute);

      if (alarmTime.isBefore(now)) {
        alarmTime = alarmTime.add(const Duration(days: 1));
      }

      final tzAlarmTime = tz.TZDateTime.from(alarmTime, tz.local);

      await _notifications.zonedSchedule(
        id: alarmTime.millisecondsSinceEpoch ~/ 1000,
        title: '⏰ $label',
        body: 'Your alarm is ringing!',
        scheduledDate: tzAlarmTime,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'alarm_channel',
            'Alarms',
            channelDescription: 'Alarm notifications',
            importance: Importance.max,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );

      return {
        'success': true,
        'scheduled_at': alarmTime.toIso8601String(),
        'label': label,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _makeCall(String contactName) async {
    try {
      final contactsStatus = await Permission.contacts.status;
      final phoneStatus = await Permission.phone.status;

      if (contactsStatus.isPermanentlyDenied) {
        await openAppSettings();
        return {
          'success': false,
          'error':
              'Contacts permission permanently denied. '
              'Please enable it in Settings.',
        };
      }

      if (phoneStatus.isPermanentlyDenied) {
        await openAppSettings();
        return {
          'success': false,
          'error':
              'Phone permission permanently denied. '
              'Please enable it in Settings.',
        };
      }

      if (!contactsStatus.isGranted) {
        final contactsResult = await Permission.contacts.request();

        if (!contactsResult.isGranted) {
          return {
            'success': false,
            'error':
                'Contacts permission denied. '
                'Please allow contacts access to make calls.',
          };
        }
      }

      if (!phoneStatus.isGranted) {
        final phoneResult = await Permission.phone.request();

        if (!phoneResult.isGranted) {
          return {
            'success': false,
            'error':
                'Phone call permission denied. '
                'Please allow phone access to make calls.',
          };
        }
      }

      final contacts = await FlutterContacts.getContacts(withProperties: true);

      if (contacts.isEmpty) {
        return {'success': false, 'error': 'No contacts found on this device.'};
      }

      Contact? match;

      try {
        match = contacts.firstWhere(
          (c) =>
              c.displayName.toLowerCase().trim() ==
              contactName.toLowerCase().trim(),
        );
      } catch (_) {
        match = null;
      }

      if (match == null || match.id.isEmpty) {
        try {
          match = contacts.firstWhere(
            (c) => c.displayName.toLowerCase().contains(
              contactName.toLowerCase().trim(),
            ),
          );
        } catch (_) {
          match = null;
        }
      }

      if (match == null || match.id.isEmpty) {
        return {
          'success': false,
          'error':
              'No contact named "$contactName" found. '
              'Please check the name and try again.',
        };
      }

      if (match.phones.isEmpty) {
        return {
          'success': false,
          'error': '${match.displayName} has no phone number saved.',
        };
      }

      final rawNumber = match.phones.first.number;
      final phoneNumber = rawNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');
      final uri = Uri.parse('tel:$phoneNumber');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return {
          'success': true,
          'message': 'Calling ${match.displayName}',
          'contact': match.displayName,
          'number': phoneNumber,
        };
      }

      return {
        'success': false,
        'error': 'Cannot open the phone dialer on this device.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to make call: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> _phoneCall(String phoneNumber) async {
    try {
      final phoneStatus = await Permission.phone.status;

      if (phoneStatus.isPermanentlyDenied) {
        await openAppSettings();
        return {
          'success': false,
          'error':
              'Phone permission permanently denied. '
              'Please enable it in Settings.',
        };
      }

      if (!phoneStatus.isGranted) {
        final phoneResult = await Permission.phone.request();

        if (!phoneResult.isGranted) {
          return {
            'success': false,
            'error':
                'Phone call permission denied. '
                'Please allow phone access to make calls.',
          };
        }
      }

      final cleanNumber = phoneNumber.replaceAll(RegExp(r'[\s\-\(\)]'), '');

      if (cleanNumber.length < 3) {
        return {
          'success': false,
          'error': 'Invalid phone number: "$phoneNumber"',
        };
      }

      final uri = Uri.parse('tel:$cleanNumber');

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        return {
          'success': true,
          'message': 'Calling $cleanNumber',
          'number': cleanNumber,
        };
      }

      return {
        'success': false,
        'error': 'Cannot open the phone dialer on this device.',
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'Failed to make call: ${e.toString()}',
      };
    }
  }

  static Future<Map<String, dynamic>> _toggleFlashlight(String state) async {
    try {
      final turnOn = state.toLowerCase() == 'on';

      final hasTorch = await TorchLight.isTorchAvailable();
      if (!hasTorch) {
        return {'success': false, 'error': 'This device has no flashlight'};
      }

      if (turnOn) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }

      return {'success': true, 'state': state};
    } on EnableTorchExistentUserException catch (_) {
      return {'success': false, 'error': 'Camera is in use by another app'};
    } on EnableTorchNotAvailableException catch (_) {
      return {'success': false, 'error': 'Torch not available'};
    } on EnableTorchException catch (e) {
      return {'success': false, 'error': 'Could not enable flashlight'};
    } on DisableTorchExistentUserException catch (_) {
      return {'success': false, 'error': 'Camera is in use by another app'};
    } on DisableTorchNotAvailableException catch (_) {
      return {'success': false, 'error': 'Torch not available'};
    } on DisableTorchException catch (e) {
      return {'success': false, 'error': 'Could not disable flashlight'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> _openWebSearch(String query) async {
    try {
      final uri = Uri.https('www.google.com', '/search', {'q': query});

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return {'success': true, 'query': query};
      }

      final fallback = await launchUrl(uri, mode: LaunchMode.platformDefault);
      if (fallback) {
        return {'success': true, 'query': query};
      }

      return {'success': false, 'error': 'Cannot open browser'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Map<String, dynamic> _getTime() {
    try {
      final now = DateTime.now();
      final time12h = DateFormat('hh:mm:ss a').format(now);
      final time24h = DateFormat('HH:mm:ss').format(now);
      final timezone = now.timeZoneName;
      final offsetHours = now.timeZoneOffset.inHours;
      final offsetMins = now.timeZoneOffset.inMinutes.abs() % 60;
      final offsetStr =
          'UTC${offsetHours >= 0 ? '+' : ''}$offsetHours'
          '${offsetMins > 0 ? ':$offsetMins' : ''}';

      return {
        'success': true,
        'time_12h': time12h,
        'time_24h': time24h,
        'timezone': timezone,
        'utc_offset': offsetStr,
        'timestamp': now.millisecondsSinceEpoch,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  static Map<String, dynamic> _getDate() {
    try {
      final now = DateTime.now();
      final dateFull = DateFormat('EEEE, MMMM d, y').format(now);
      final dateShort = DateFormat('dd/MM/yyyy').format(now);
      final dateIso = DateFormat('yyyy-MM-dd').format(now);
      final dayOfWeek = DateFormat('EEEE').format(now);
      final month = DateFormat('MMMM').format(now);

      return {
        'success': true,
        'date_full': dateFull,
        'date_short': dateShort,
        'date_iso': dateIso,
        'day_of_week': dayOfWeek,
        'month': month,
        'day': now.day,
        'year': now.year,
      };
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class StorageService {
  // Using the modern SharedPreferencesAsync API
  static final SharedPreferencesAsync _prefs = SharedPreferencesAsync();
  static const String _historyKey = 'measurement_history';

  // Save a new measurement scan
  static Future<void> saveMeasurement(Map<String, dynamic> measurements) async {
    // 1. Fetch existing history
    final String? existingData = await _prefs.getString(_historyKey);
    List<dynamic> history = [];
    if (existingData != null) {
      history = jsonDecode(existingData);
    }

    // 2. Attach a date/time stamp
    final entry = {
      'date': DateTime.now().toIso8601String(),
      'measurements': measurements,
    };

    // 3. Add to the top of the list and save back to local storage
    history.insert(0, entry);
    await _prefs.setString(_historyKey, jsonEncode(history));
  }

  // Load all past scans
  static Future<List<dynamic>> getHistory() async {
    final String? existingData = await _prefs.getString(_historyKey);
    if (existingData != null) {
      return jsonDecode(existingData);
    }
    return [];
  }
}

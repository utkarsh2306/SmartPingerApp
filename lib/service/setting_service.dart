import 'package:shared_preferences/shared_preferences.dart';

class SettingsService {
  static const String _daysLimitKey = 'days_limit';
  static const int _defaultDaysLimit = 10;

  // Save days limit
  static Future<void> setDaysLimit(int days) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_daysLimitKey, days);
  }

  // Get days limit (returns 10 if not set)
  static Future<int> getDaysLimit() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_daysLimitKey) ?? _defaultDaysLimit;
  }

  // Get available days options
  static List<int> getDaysOptions() {
    return [7, 10, 15, 30, 60, 90];
  }

  // Add these to SettingsService class
  static Future<int> getSelectedSim() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('selected_sim') ?? 1; // 1 = SIM 1, 2 = SIM 2
  }

  static Future<void> setSelectedSim(int sim) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('selected_sim', sim);
  }
}

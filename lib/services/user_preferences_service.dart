import 'package:shared_preferences/shared_preferences.dart';

class UserPreferencesService {
  static const String _hasSeenQueueInstructionKey =
      'has_seen_queue_instruction';
  static const String _isFirstTimeUserKey = 'is_first_time_user';

  /// Check if user has seen the queue instruction
  static Future<bool> hasSeenQueueInstruction() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_hasSeenQueueInstructionKey) ?? false;
  }

  /// Mark that user has seen the queue instruction
  static Future<void> markQueueInstructionAsSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_hasSeenQueueInstructionKey, true);
  }

  /// Check if this is a first-time user
  static Future<bool> isFirstTimeUser() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isFirstTimeUserKey) ?? true;
  }

  /// Mark user as no longer a first-time user
  static Future<void> markAsReturningUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isFirstTimeUserKey, false);
  }

  /// Reset all user preferences (for testing purposes)
  static Future<void> resetPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_hasSeenQueueInstructionKey);
    await prefs.remove(_isFirstTimeUserKey);
  }
}








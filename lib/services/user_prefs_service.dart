import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Stores user preferences for the Feed Discovery system on-device (JSON file).
///
/// Persisted data:
/// - `interests`: list of hashtag strings the user cares about.
/// - `interests_set`: bool, true once the user has completed interest onboarding.
/// - `viewed_hashtags`: map of hashtag → view count (for Scheme B bonus).
///
/// No data ever leaves the device.
class UserPrefsService {
  UserPrefsService._();

  static final UserPrefsService instance = UserPrefsService._();

  static const _fileName = 'user_prefs.json';

  Map<String, dynamic> _data = {};
  bool _loaded = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_loaded) return;
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        _data = jsonDecode(raw) as Map<String, dynamic>;
      }
    } catch (_) {
      _data = {};
    }
    _loaded = true;
  }

  // ── Interests ─────────────────────────────────────────────────────────────

  /// Returns the user's selected interest hashtags (without '#').
  List<String> get interests =>
      List<String>.from(_data['interests'] as List? ?? []);

  /// Whether the user has completed the interest-selection step.
  bool get hasSetInterests => _data['interests_set'] == true;

  /// Saves the user's chosen interest hashtags and marks onboarding complete.
  Future<void> saveInterests(List<String> tags) async {
    _data = {
      ..._data,
      'interests': tags,
      'interests_set': true,
    };
    await _save();
  }

  // ── View tracking (Scheme B bonus) ────────────────────────────────────────

  /// Returns a map of hashtag → how many times the user has viewed it.
  Map<String, int> get viewedHashtags =>
      Map<String, int>.from(_data['viewed_hashtags'] as Map? ?? {});

  /// Increments the view count for [hashtag] by 1.
  Future<void> recordHashtagView(String hashtag) async {
    final views = viewedHashtags;
    views[hashtag] = (views[hashtag] ?? 0) + 1;
    _data = {..._data, 'viewed_hashtags': views};
    await _save();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode(_data));
    } catch (_) {}
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}

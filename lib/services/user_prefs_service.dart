import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Locale;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'package:mobile/models/asset_transport_policy.dart';

/// Stores user preferences for the Feed Discovery system on-device (JSON file).
///
/// Persisted data:
/// - `interests`: list of hashtag strings the user cares about.
/// - `interests_set`: bool, true once the user has completed interest onboarding.
/// - `viewed_hashtags`: map of hashtag → view count (for Scheme B bonus).
/// - `asset_transport_policy`: peer media transport policy.
/// - `ui_locale`: optional app locale override.
///
/// No data ever leaves the device.
class UserPrefsService {
  UserPrefsService._();

  static final UserPrefsService instance = UserPrefsService._();

  static const _fileName = 'user_prefs.json';

  Map<String, dynamic> _data = {};
  bool _loaded = false;
  final ValueNotifier<Locale?> _uiLocaleNotifier = ValueNotifier<Locale?>(null);

  ValueListenable<Locale?> get uiLocaleListenable => _uiLocaleNotifier;

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
    _uiLocaleNotifier.value = uiLocale;
    _loaded = true;
  }

  // ── Interests ─────────────────────────────────────────────────────────────

  /// Returns the user's selected interest hashtags (without '#').
  List<String> get interests =>
      List<String>.from(_data['interests'] as List? ?? []);

  /// Version string for the currently accepted community terms gate.
  String? get ugcTermsVersion => _data['ugc_terms_version'] as String?;

  /// Timestamp when the current device accepted the community terms.
  DateTime? get ugcTermsAcceptedAt {
    final raw = _data['ugc_terms_accepted_at'] as String?;
    if (raw == null || raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toUtc();
  }

  bool hasAcceptedUgcTerms(String version) {
    return ugcTermsVersion == version && ugcTermsAcceptedAt != null;
  }

  Future<void> acceptUgcTerms(String version) async {
    _data = {
      ..._data,
      'ugc_terms_version': version,
      'ugc_terms_accepted_at': DateTime.now().toUtc().toIso8601String(),
    };
    await _save();
  }

  /// Whether the user has completed the interest-selection step.
  bool get hasSetInterests => _data['interests_set'] == true;

  /// Saves the user's chosen interest hashtags and marks onboarding complete.
  Future<void> saveInterests(List<String> tags) async {
    _data = {..._data, 'interests': tags, 'interests_set': true};
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

  // ── Asset transport ─────────────────────────────────────────────────────

  AssetTransportPolicy get assetTransportPolicy =>
      parseAssetTransportPolicy(_data['asset_transport_policy'] as String?);

  Future<void> saveAssetTransportPolicy(AssetTransportPolicy policy) async {
    _data = {..._data, 'asset_transport_policy': policy.storageValue};
    await _save();
  }

  // ── UI language ───────────────────────────────────────────────────────────

  Locale? get uiLocale => _decodeLocale(_data['ui_locale'] as String?);

  Future<void> saveUiLocale(Locale? locale) async {
    final localeTag = _encodeLocale(locale);
    final nextData = {..._data};
    if (localeTag == null) {
      nextData.remove('ui_locale');
    } else {
      nextData['ui_locale'] = localeTag;
    }
    _data = nextData;
    _uiLocaleNotifier.value = locale;
    await _save();
  }

  // ── CDN acceleration ──────────────────────────────────────────────────────

  /// Whether CDN fetch/upload is enabled.
  ///
  /// Defaults to true until the user explicitly changes the setting.
  bool get cdnEnabled => _data['cdn_enabled'] as bool? ?? true;

  /// Whether CDN upload specifically is enabled.
  ///
  /// Defaults to true until the user explicitly changes the setting.
  /// Has no effect when [cdnEnabled] is false.
  bool get cdnUploadEnabled => _data['cdn_upload_enabled'] as bool? ?? true;

  Future<void> saveCdnEnabled(bool enabled) async {
    _data = {..._data, 'cdn_enabled': enabled};
    await _save();
  }

  Future<void> saveCdnUploadEnabled(bool enabled) async {
    _data = {..._data, 'cdn_upload_enabled': enabled};
    await _save();
  }

  // ── Footprint Map privacy ──────────────────────────────────────────────────

  /// Whether the footprint map is visible to other users.
  /// Defaults to false (private) until the user explicitly enables it.
  bool get footprintMapPublic =>
      _data['footprint_map_public'] as bool? ?? false;

  Future<void> saveFootprintMapPublic(bool isPublic) async {
    _data = {..._data, 'footprint_map_public': isPublic};
    await _save();
  }

  // ── Session safety ────────────────────────────────────────────────────────

  /// Whether a saved account should require local unlock on app open/resume.
  /// Defaults to false unless the user explicitly enables it.
  bool get safeModeEnabled => _data['safe_mode_enabled'] as bool? ?? false;

  Future<void> saveSafeModeEnabled(bool enabled) async {
    _data = {..._data, 'safe_mode_enabled': enabled};
    await _save();
  }

  Future<void> clearAll() async {
    _data = {};
    _loaded = true;
    _uiLocaleNotifier.value = null;
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
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

  static String? _encodeLocale(Locale? locale) {
    if (locale == null) return null;
    if ((locale.countryCode ?? '').isEmpty) return locale.languageCode;
    return '${locale.languageCode}_${locale.countryCode}';
  }

  static Locale? _decodeLocale(String? value) {
    return switch (value) {
      null || '' => null,
      'en' => const Locale('en'),
      'ja' => const Locale('ja'),
      'zh' => const Locale('zh'),
      'zh_TW' || 'zh-TW' => const Locale('zh', 'TW'),
      _ => null,
    };
  }
}

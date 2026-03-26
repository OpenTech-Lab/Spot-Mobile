import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Centralised app configuration.
abstract final class AppConfig {
  AppConfig._();

  static const metadataPageSize = 20;

  static String get supabaseUrl => _requireEnv('SUPABASE_URL');

  static String get supabaseAnonKey => _requireEnv('SUPABASE_ANON_KEY');

  static String? get cdnBaseUrl => _optionalEnv('CDN_BASE_URL');

  static String? get cdnPresignUrl => _optionalEnv('CDN_PRESIGN_URL');

  static String _requireEnv(String key) {
    final value = _optionalEnv(key);
    if (value == null || value.isEmpty) {
      throw StateError('Missing required environment variable: $key');
    }
    return value;
  }

  static String? _optionalEnv(String key) {
    final value = dotenv.env[key]?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }
}

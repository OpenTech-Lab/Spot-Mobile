import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Offline reverse-geocoding from the bundled Natural Earth SQLite database.
///
/// Usage:
///   await GeoLookup.instance.init();   // once at startup
///   final loc = GeoLookup.instance.nearest(lat, lon);
///   print(loc);  // GeoLocation(city:'Tokyo', country:'Japan')
///
/// After [init] all queries are synchronous in-memory operations — no I/O.
class GeoLookup {
  GeoLookup._();
  static final instance = GeoLookup._();

  static const String _assetPath = 'assets/geo/places.db';
  static const String _dbFileName = 'places.db';

  List<_City> _cities = [];
  bool _ready = false;

  bool get isReady => _ready;

  // ── Init ──────────────────────────────────────────────────────────────────

  /// Copies the bundled SQLite to the documents directory (once), loads all
  /// city rows into memory, then closes the file handle.
  Future<void> init() async {
    if (_ready) return;

    final dbPath = await _ensureDatabase();
    final db = await openDatabase(dbPath, readOnly: true);

    final rows = await db.rawQuery(
      'SELECT name, country, lat, lon FROM cities',
    );
    await db.close();

    _cities = rows
        .map((r) => _City(
              name: r['name'] as String,
              country: r['country'] as String,
              lat: r['lat'] as double,
              lon: r['lon'] as double,
            ))
        .toList();

    _ready = true;
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Returns the [GeoLocation] of the nearest city to ([lat], [lon]).
  /// Returns null if [init] has not completed yet.
  GeoLocation? nearest(double lat, double lon) {
    if (!_ready || _cities.isEmpty) return null;

    _City best = _cities.first;
    double bestDist = _squaredDist(lat, lon, best);

    for (final city in _cities) {
      final d = _squaredDist(lat, lon, city);
      if (d < bestDist) {
        bestDist = d;
        best = city;
      }
    }

    return GeoLocation(city: best.name, country: best.country);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Equirectangular squared distance — fast, accurate enough for nearest-city.
  double _squaredDist(double lat, double lon, _City c) {
    final dlat = lat - c.lat;
    final dlon = (lon - c.lon) * cos(lat * pi / 180);
    return dlat * dlat + dlon * dlon;
  }

  /// Returns the on-device path to the SQLite file, copying from assets
  /// the first time it is needed.
  Future<String> _ensureDatabase() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final dest = p.join(docsDir.path, _dbFileName);

    if (!File(dest).existsSync()) {
      final data = await rootBundle.load(_assetPath);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await File(dest).writeAsBytes(bytes, flush: true);
    }

    return dest;
  }
}

// ── Value objects ──────────────────────────────────────────────────────────

class GeoLocation {
  const GeoLocation({required this.city, required this.country});

  final String city;
  final String country;

  @override
  String toString() => '$country/$city';
}

class _City {
  const _City({
    required this.name,
    required this.country,
    required this.lat,
    required this.lon,
  });

  final String name;
  final String country;
  final double lat;
  final double lon;
}

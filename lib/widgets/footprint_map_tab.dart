import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/theme/spot_theme.dart';

/// A world map tab showing countries the user has visited (derived from post
/// GPS coordinates). Visited countries render white; all others render grey.
/// Backed by the bundled Natural Earth 1:110m country boundaries GeoJSON.
class FootprintMapTab extends StatefulWidget {
  const FootprintMapTab({super.key, required this.posts});

  final List<MediaPost> posts;

  @override
  State<FootprintMapTab> createState() => _FootprintMapTabState();
}

class _FootprintMapTabState extends State<FootprintMapTab> {
  List<_CountryPolygon> _allPolygons = [];
  Set<String> _visitedNames = {};
  bool _loading = true;

  /// Maps alternate country name spellings from GeoLookup cities table
  /// to the ADMIN property used in the Natural Earth admin-0 GeoJSON.
  static const Map<String, String> _aliases = {
    'united states': 'united states of america',
    'czech republic': 'czechia',
    'ivory coast': "côte d'ivoire",
    'republic of congo': 'republic of the congo',
    'north korea': 'dem. rep. korea',
    'south korea': 'republic of korea',
    'tanzania': 'united republic of tanzania',
    'bolivia': 'bolivia',
    'venezuela': 'venezuela',
    'vietnam': 'vietnam',
    'laos': 'laos',
    'moldova': 'moldova',
    'russia': 'russia',
  };

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void didUpdateWidget(FootprintMapTab old) {
    super.didUpdateWidget(old);
    if (old.posts != widget.posts) _computeVisited();
  }

  Future<void> _init() async {
    await _loadPolygons();
    _computeVisited();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPolygons() async {
    final raw = await rootBundle.loadString('assets/geo/countries.geojson');
    final geojson = jsonDecode(raw) as Map<String, dynamic>;
    final features = geojson['features'] as List<dynamic>;
    final polygons = <_CountryPolygon>[];

    for (final feature in features) {
      final props = feature['properties'] as Map<String, dynamic>;
      final name = props['ADMIN'] as String? ?? '';
      final geometry = feature['geometry'] as Map<String, dynamic>;
      final type = geometry['type'] as String;
      final coords = geometry['coordinates'] as List<dynamic>;

      if (type == 'Polygon') {
        final ring = _parseRing(coords[0] as List<dynamic>);
        if (ring.isNotEmpty) {
          polygons.add(_CountryPolygon(name: name, points: ring));
        }
      } else if (type == 'MultiPolygon') {
        for (final poly in coords) {
          final ring = _parseRing((poly as List<dynamic>)[0] as List<dynamic>);
          if (ring.isNotEmpty) {
            polygons.add(_CountryPolygon(name: name, points: ring));
          }
        }
      }
    }

    _allPolygons = polygons;
  }

  List<LatLng> _parseRing(List<dynamic> ring) => ring
      .whereType<List<dynamic>>()
      .where((c) => c.length >= 2)
      .map((c) => LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()))
      .toList(growable: false);

  void _computeVisited() {
    if (!GeoLookup.instance.isReady) return;
    final visited = <String>{};
    for (final post in widget.posts) {
      if (!post.hasGps || post.isVirtual || post.isDangerMode) continue;
      final loc = GeoLookup.instance.nearest(post.latitude!, post.longitude!);
      if (loc != null) visited.add(_normalize(loc.country));
    }
    if (mounted) setState(() => _visitedNames = visited);
  }

  String _normalize(String name) {
    final lower = name.trim().toLowerCase();
    return _aliases[lower] ?? lower;
  }

  List<Polygon> _buildPolygons() {
    return _allPolygons.map((cp) {
      final isVisited = _visitedNames.contains(_normalize(cp.name));
      return Polygon(
        points: cp.points,
        color: isVisited
            ? Colors.white.withAlpha(220)
            : SpotColors.overlay.withAlpha(100),
        borderColor: SpotColors.border,
        borderStrokeWidth: 0.4,
      );
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            color: SpotColors.accent,
            strokeWidth: 1,
          ),
        ),
      );
    }

    final count = _visitedNames.length;

    return Stack(
      children: [
        FlutterMap(
          options: MapOptions(
            initialCenter: const LatLng(20, 0),
            initialZoom: 1.5,
            minZoom: 1.0,
            maxZoom: 6.0,
            backgroundColor: SpotColors.bg,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
            ),
          ),
          children: [
            PolygonLayer(polygons: _buildPolygons()),
          ],
        ),
        Positioned(
          top: SpotSpacing.md,
          left: SpotSpacing.md,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: SpotSpacing.md,
              vertical: SpotSpacing.xs,
            ),
            decoration: SpotDecoration.cardBordered(),
            child: Text(
              '$count ${count == 1 ? 'country' : 'countries'} visited',
              style: SpotType.caption.copyWith(
                color: SpotColors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CountryPolygon {
  const _CountryPolygon({required this.name, required this.points});

  final String name;
  final List<LatLng> points;
}

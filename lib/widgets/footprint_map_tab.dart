import 'dart:async';
import 'dart:convert';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/theme/spot_theme.dart';

const double footprintMapMinZoom = 0.5;
const double footprintMapMaxZoom = 6.0;
const double footprintMapZoomStep = 0.75;
const String footprintMapTitle = 'Footprint Map';
const String footprintMapSelectionHint = 'Tap a country to see visit count';

typedef FootprintCountryResolver =
    GeoLocation? Function(double latitude, double longitude);
typedef FootprintCountryShapeLoader =
    Future<List<FootprintCountryShape>> Function();

/// Maps alternate country name spellings from GeoLookup cities table
/// to the ADMIN property used in the Natural Earth admin-0 GeoJSON.
const Map<String, String> footprintCountryAliases = {
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

String normalizeFootprintCountryName(String name) {
  final lower = name.trim().toLowerCase();
  if (lower.isEmpty) return lower;
  return footprintCountryAliases[lower] ?? lower;
}

double clampFootprintMapZoom(double zoom) =>
    zoom.clamp(footprintMapMinZoom, footprintMapMaxZoom).toDouble();

double stepFootprintMapZoom(double zoom, double delta) =>
    clampFootprintMapZoom(zoom + delta);

String footprintCountryVisitLabel(String countryName, int count) =>
    '$countryName · $count ${count == 1 ? 'visit' : 'visits'}';

Color footprintCountryFillColor(int visitCount) {
  if (visitCount <= 0) return Colors.transparent;
  if (visitCount == 1) return const Color(0xFF424242);
  if (visitCount <= 5) return const Color(0xFF7A7A7A);
  if (visitCount <= 10) return const Color(0xFFA8A8A8);
  return Colors.white;
}

Map<String, int> buildFootprintCountryVisitCounts(
  Iterable<MediaPost> posts, {
  FootprintCountryResolver? resolveCountry,
}) {
  final effectiveResolver =
      resolveCountry ??
      (double latitude, double longitude) {
        if (!GeoLookup.instance.isReady) return null;
        return GeoLookup.instance.nearest(latitude, longitude);
      };

  final counts = <String, int>{};
  for (final post in posts) {
    if (!post.hasGps || post.isVirtual || post.isDangerMode) continue;
    final geo = effectiveResolver(post.latitude!, post.longitude!);
    if (geo == null) continue;
    final normalizedCountry = normalizeFootprintCountryName(geo.country);
    if (normalizedCountry.isEmpty) continue;
    counts.update(normalizedCountry, (value) => value + 1, ifAbsent: () => 1);
  }
  return counts;
}

Future<List<FootprintCountryShape>> loadFootprintCountryShapes({
  AssetBundle? bundle,
}) async {
  final raw = await (bundle ?? rootBundle).loadString(
    'assets/geo/countries.geojson',
  );
  final geojson = jsonDecode(raw) as Map<String, dynamic>;
  final features = geojson['features'] as List<dynamic>;
  final polygons = <FootprintCountryShape>[];

  for (final feature in features) {
    final props = feature['properties'] as Map<String, dynamic>;
    final name = props['ADMIN'] as String? ?? '';
    final geometry = feature['geometry'] as Map<String, dynamic>;
    final type = geometry['type'] as String;
    final coords = geometry['coordinates'] as List<dynamic>;

    if (type == 'Polygon') {
      final ring = _parseFootprintRing(coords[0] as List<dynamic>);
      if (ring.isNotEmpty) {
        polygons.add(FootprintCountryShape(name: name, points: ring));
      }
    } else if (type == 'MultiPolygon') {
      for (final polygon in coords) {
        final ring = _parseFootprintRing(
          (polygon as List<dynamic>)[0] as List<dynamic>,
        );
        if (ring.isNotEmpty) {
          polygons.add(FootprintCountryShape(name: name, points: ring));
        }
      }
    }
  }

  return polygons;
}

List<LatLng> _parseFootprintRing(List<dynamic> ring) => ring
    .whereType<List<dynamic>>()
    .where((coordinate) => coordinate.length >= 2)
    .map(
      (coordinate) => LatLng(
        (coordinate[1] as num).toDouble(),
        (coordinate[0] as num).toDouble(),
      ),
    )
    .toList(growable: false);

class FootprintCountryShape {
  const FootprintCountryShape({required this.name, required this.points});

  final String name;
  final List<LatLng> points;
}

class FootprintMapScreen extends StatelessWidget {
  const FootprintMapScreen({
    super.key,
    required this.posts,
    this.shapeLoader,
    this.resolveCountry,
  });

  final List<MediaPost> posts;
  final FootprintCountryShapeLoader? shapeLoader;
  final FootprintCountryResolver? resolveCountry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        automaticallyImplyLeading: false,
        leading: IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(CupertinoIcons.back, size: 20),
          color: SpotColors.textSecondary,
        ),
        title: Text(l10n.footprintMapTitle, style: SpotType.subheading),
      ),
      body: SafeArea(
        top: false,
        child: FootprintMapTab(
          posts: posts,
          isFullScreen: true,
          shapeLoader: shapeLoader,
          resolveCountry: resolveCountry,
        ),
      ),
    );
  }
}

/// A world map tab showing countries the user has visited (derived from post
/// GPS coordinates). Country fills get brighter as visit counts increase.
/// Backed by the bundled Natural Earth 1:110m country boundaries GeoJSON.
class FootprintMapTab extends StatefulWidget {
  const FootprintMapTab({
    super.key,
    required this.posts,
    this.isFullScreen = false,
    this.shapeLoader,
    this.resolveCountry,
  });

  final List<MediaPost> posts;
  final bool isFullScreen;
  final FootprintCountryShapeLoader? shapeLoader;
  final FootprintCountryResolver? resolveCountry;

  @override
  State<FootprintMapTab> createState() => _FootprintMapTabState();
}

class _FootprintMapTabState extends State<FootprintMapTab> {
  static const double _selectionPopupWidth = 56;
  static const double _selectionPopupHeight = 44;
  static final LatLngBounds _worldBounds = LatLngBounds(
    const LatLng(-75, -180),
    const LatLng(85, 180),
  );

  final LayerHitNotifier<String> _hitNotifier = ValueNotifier(null);
  late final MapController _mapController;
  late double _currentZoom;
  List<FootprintCountryShape> _allPolygons = const [];
  Map<String, int> _visitCounts = const {};
  bool _loading = true;
  bool _isMapReady = false;
  String? _selectedCountryName;
  int? _selectedCountryVisits;
  Offset? _selectedCountryTapPosition;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _currentZoom = footprintMapMinZoom;
    _init();
  }

  @override
  void didUpdateWidget(FootprintMapTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.shapeLoader != widget.shapeLoader) {
      unawaited(_reloadPolygons());
    }
    if (oldWidget.posts != widget.posts ||
        oldWidget.resolveCountry != widget.resolveCountry) {
      _recomputeVisitCounts();
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final polygons = await _loadPolygons();
    final counts = _buildVisitCounts();
    if (!mounted) return;
    setState(() {
      _allPolygons = polygons;
      _visitCounts = counts;
      _loading = false;
    });
  }

  Future<void> _reloadPolygons() async {
    setState(() => _loading = true);
    final polygons = await _loadPolygons();
    if (!mounted) return;
    setState(() {
      _allPolygons = polygons;
      _loading = false;
    });
  }

  Future<List<FootprintCountryShape>> _loadPolygons() async {
    final loader = widget.shapeLoader ?? loadFootprintCountryShapes;
    return loader();
  }

  Map<String, int> _buildVisitCounts() => buildFootprintCountryVisitCounts(
    widget.posts,
    resolveCountry: widget.resolveCountry,
  );

  void _recomputeVisitCounts() {
    final counts = _buildVisitCounts();
    if (!mounted) {
      _visitCounts = counts;
      return;
    }
    setState(() {
      _visitCounts = counts;
      if (_selectedCountryName != null) {
        _selectedCountryVisits =
            counts[normalizeFootprintCountryName(_selectedCountryName!)] ?? 0;
        if ((_selectedCountryVisits ?? 0) <= 0) {
          _selectedCountryName = null;
          _selectedCountryVisits = null;
          _selectedCountryTapPosition = null;
        }
      }
    });
  }

  void _openFullScreen() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => FootprintMapScreen(
          posts: widget.posts,
          shapeLoader: widget.shapeLoader,
          resolveCountry: widget.resolveCountry,
        ),
      ),
    );
  }

  void _adjustZoom(double delta) {
    if (!_isMapReady) return;
    final nextZoom = stepFootprintMapZoom(_currentZoom, delta);
    if ((nextZoom - _currentZoom).abs() < 0.01) return;

    _mapController.move(
      _mapController.camera.center,
      nextZoom,
      id: 'footprint-map-zoom',
    );
    setState(() => _currentZoom = nextZoom);
  }

  void _handlePositionChanged(MapCamera camera, bool hasGesture) {
    final nextZoom = clampFootprintMapZoom(camera.zoom);
    final shouldClearSelection =
        hasGesture && _selectedCountryTapPosition != null;
    if ((_currentZoom - nextZoom).abs() < 0.01 && !shouldClearSelection) {
      return;
    }
    setState(() {
      _currentZoom = nextZoom;
      if (shouldClearSelection) {
        _selectedCountryName = null;
        _selectedCountryVisits = null;
        _selectedCountryTapPosition = null;
      }
    });
  }

  void _handleCountryTap(Offset tapPosition) {
    final hitValues = _hitNotifier.value?.hitValues.toSet().toList(
      growable: false,
    );
    if (hitValues == null || hitValues.isEmpty) {
      if (_selectedCountryName == null &&
          _selectedCountryVisits == null &&
          _selectedCountryTapPosition == null) {
        return;
      }
      setState(() {
        _selectedCountryName = null;
        _selectedCountryVisits = null;
        _selectedCountryTapPosition = null;
      });
      return;
    }

    final countryName = hitValues.first;
    final visitCount =
        _visitCounts[normalizeFootprintCountryName(countryName)] ?? 0;

    if (visitCount <= 0) {
      setState(() {
        _selectedCountryName = null;
        _selectedCountryVisits = null;
        _selectedCountryTapPosition = null;
      });
      return;
    }

    setState(() {
      _selectedCountryName = countryName;
      _selectedCountryVisits = visitCount;
      _selectedCountryTapPosition = tapPosition;
    });
  }

  double _clampPopupLeft(double desiredLeft, double maxWidth) {
    return desiredLeft.clamp(
      SpotSpacing.md,
      maxWidth - _selectionPopupWidth - SpotSpacing.md,
    );
  }

  double _clampPopupTop(double desiredTop, double maxHeight) {
    return desiredTop.clamp(
      SpotSpacing.md,
      maxHeight - _selectionPopupHeight - SpotSpacing.md,
    );
  }

  List<Polygon<String>> _buildPolygons() {
    return _allPolygons
        .map((shape) {
          final normalizedName = normalizeFootprintCountryName(shape.name);
          final visitCount = _visitCounts[normalizedName] ?? 0;
          final isSelected =
              _selectedCountryName != null &&
              normalizeFootprintCountryName(_selectedCountryName!) ==
                  normalizedName;

          return Polygon<String>(
            points: shape.points,
            hitValue: shape.name,
            color: footprintCountryFillColor(visitCount),
            borderColor: isSelected ? SpotColors.accent : SpotColors.border,
            borderStrokeWidth: isSelected ? 0.9 : 0.4,
          );
        })
        .toList(growable: false);
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

    final l10n = AppLocalizations.of(context)!;
    final visitedCountryCount = _visitCounts.length;
    final canZoomIn = _currentZoom < footprintMapMaxZoom - 0.01;
    final canZoomOut = _currentZoom > footprintMapMinZoom + 0.01;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tapPosition = _selectedCountryTapPosition;
        final showPopup =
            widget.isFullScreen &&
            tapPosition != null &&
            (_selectedCountryVisits ?? 0) > 0;
        final popupLeft = showPopup
            ? _clampPopupLeft(
                tapPosition.dx - (_selectionPopupWidth / 2),
                constraints.maxWidth,
              )
            : 0.0;
        final popupTop = showPopup
            ? _clampPopupTop(
                tapPosition.dy - _selectionPopupHeight - SpotSpacing.md,
                constraints.maxHeight,
              )
            : 0.0;

        return Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCameraFit: CameraFit.bounds(
                  bounds: _worldBounds,
                  padding: const EdgeInsets.all(8),
                ),
                minZoom: footprintMapMinZoom,
                maxZoom: footprintMapMaxZoom,
                backgroundColor: SpotColors.bg,
                interactionOptions: InteractionOptions(
                  flags: widget.isFullScreen
                      ? InteractiveFlag.drag |
                            InteractiveFlag.pinchZoom |
                            InteractiveFlag.doubleTapZoom
                      : InteractiveFlag.pinchZoom |
                            InteractiveFlag.doubleTapZoom,
                ),
                onMapReady: () {
                  if (!mounted) return;
                  setState(() {
                    _isMapReady = true;
                    _currentZoom = clampFootprintMapZoom(
                      _mapController.camera.zoom,
                    );
                  });
                },
                onPositionChanged: _handlePositionChanged,
              ),
              children: [
                GestureDetector(
                  onTapUp: (details) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      _handleCountryTap(details.localPosition);
                    });
                  },
                  child: PolygonLayer<String>(
                    hitNotifier: _hitNotifier,
                    simplificationTolerance: 0,
                    polygons: _buildPolygons(),
                  ),
                ),
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
                  l10n.footprintCountriesVisited(visitedCountryCount),
                  style: SpotType.caption.copyWith(
                    color: SpotColors.textSecondary,
                  ),
                ),
              ),
            ),
            if (!widget.isFullScreen)
              Positioned(
                top: SpotSpacing.md,
                right: SpotSpacing.md,
                child: _FootprintMapIconButton(
                  icon: CupertinoIcons.arrow_up_left_arrow_down_right,
                  tooltip: l10n.openFullScreenMap,
                  onTap: _openFullScreen,
                ),
              ),
            if (widget.isFullScreen)
              Positioned(
                right: SpotSpacing.md,
                bottom: SpotSpacing.md,
                child: _FootprintMapZoomControls(
                  canZoomIn: _isMapReady && canZoomIn,
                  canZoomOut: _isMapReady && canZoomOut,
                  onZoomIn: () => _adjustZoom(footprintMapZoomStep),
                  onZoomOut: () => _adjustZoom(-footprintMapZoomStep),
                  zoomInTooltip: l10n.zoomIn,
                  zoomOutTooltip: l10n.zoomOut,
                ),
              ),
            if (showPopup)
              Positioned(
                left: popupLeft,
                top: popupTop,
                child: _FootprintMapSelectionPopup(
                  visits: _selectedCountryVisits!,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FootprintMapIconButton extends StatelessWidget {
  const _FootprintMapIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: SpotColors.bg.withAlpha(224),
            borderRadius: BorderRadius.circular(SpotRadius.sm),
            border: Border.all(color: SpotColors.border, width: 0.5),
          ),
          child: Icon(icon, size: 16, color: SpotColors.textPrimary),
        ),
      ),
    );
  }
}

class _FootprintMapZoomControls extends StatelessWidget {
  const _FootprintMapZoomControls({
    required this.canZoomIn,
    required this.canZoomOut,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.zoomInTooltip,
    required this.zoomOutTooltip,
  });

  final bool canZoomIn;
  final bool canZoomOut;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final String zoomInTooltip;
  final String zoomOutTooltip;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: SpotColors.bg.withAlpha(224),
        borderRadius: BorderRadius.circular(SpotRadius.sm),
        border: Border.all(color: SpotColors.border, width: 0.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _FootprintMapZoomButton(
            icon: CupertinoIcons.plus,
            tooltip: zoomInTooltip,
            isEnabled: canZoomIn,
            onTap: onZoomIn,
          ),
          const SizedBox(
            width: 36,
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: SpotColors.border,
            ),
          ),
          _FootprintMapZoomButton(
            icon: CupertinoIcons.minus,
            tooltip: zoomOutTooltip,
            isEnabled: canZoomOut,
            onTap: onZoomOut,
          ),
        ],
      ),
    );
  }
}

class _FootprintMapZoomButton extends StatelessWidget {
  const _FootprintMapZoomButton({
    required this.icon,
    required this.tooltip,
    required this.isEnabled,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool isEnabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconColor = isEnabled
        ? SpotColors.textPrimary
        : SpotColors.textTertiary;

    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: isEnabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: 36,
          height: 36,
          child: Center(child: Icon(icon, size: 16, color: iconColor)),
        ),
      ),
    );
  }
}

class _FootprintMapSelectionPopup extends StatelessWidget {
  const _FootprintMapSelectionPopup({required this.visits});

  final int visits;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('footprint_map_visit_popup'),
      width: _FootprintMapTabState._selectionPopupWidth,
      height: _FootprintMapTabState._selectionPopupHeight,
      decoration: BoxDecoration(
        color: SpotColors.bg.withAlpha(232),
        borderRadius: BorderRadius.circular(SpotRadius.sm),
        border: Border.all(color: SpotColors.accent.withAlpha(120), width: 0.5),
      ),
      child: Center(
        child: Text(
          '$visits',
          style: SpotType.subheading.copyWith(
            color: SpotColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}

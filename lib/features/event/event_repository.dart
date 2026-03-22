import 'dart:async';

import 'package:mobile/features/nostr/nostr_models.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';

/// Aggregates raw [NostrEvent]s from relays into [CivicEvent] domain objects.
///
/// The repository maintains an in-memory cache of [CivicEvent]s keyed by
/// hashtag.  Callers can stream live updates or query the current snapshot.
class EventRepository {
  EventRepository({required NostrService nostrService})
      : _nostr = nostrService;

  final NostrService _nostr;

  /// In-memory cache: hashtag → CivicEvent
  final Map<String, CivicEvent> _cache = {};

  /// Broadcast stream of updated [CivicEvent]s.
  final _controller = StreamController<CivicEvent>.broadcast();

  String? _globalSubId;

  // ── Subscription ──────────────────────────────────────────────────────────

  /// Returns a stream of [CivicEvent] objects as new posts arrive.
  ///
  /// Subscribes to kind-1 Nostr events from all connected relays.
  /// Each incoming event is parsed into a [MediaPost] and merged into
  /// the appropriate [CivicEvent] for its hashtag.
  Stream<CivicEvent> subscribeToEvents() {
    _globalSubId ??= _nostr.subscribe(
      [
        NostrFilter(kinds: [1], limit: 50),
      ],
      _handleNostrEvent,
    );

    return _controller.stream;
  }

  // ── Query ─────────────────────────────────────────────────────────────────

  /// Returns the [CivicEvent] for [hashtag], fetching from relay if needed.
  Future<CivicEvent?> getEventByTag(String hashtag) async {
    if (_cache.containsKey(hashtag)) return _cache[hashtag];

    // Subscribe specifically for this hashtag to hydrate the cache.
    final completer = Completer<CivicEvent?>();
    String? subId;

    subId = _nostr.subscribe(
      [
        NostrFilter(
          kinds: [1],
          limit: 100,
          tags: {
            't': [hashtag],
          },
        ),
      ],
      (event) {
        _handleNostrEvent(event);
        if (!completer.isCompleted && _cache.containsKey(hashtag)) {
          completer.complete(_cache[hashtag]);
        }
      },
    );

    // Give the relay 5 seconds to respond.
    final result = await completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => _cache[hashtag],
    );

    _nostr.unsubscribe(subId);
    return result;
  }

  /// Returns a snapshot of all cached [CivicEvent]s, newest-first.
  List<CivicEvent> getAllEvents() {
    final events = _cache.values.toList();
    events.sort((a, b) => b.firstSeen.compareTo(a.firstSeen));
    return events;
  }

  // ── Local mutation ────────────────────────────────────────────────────────

  /// Adds a locally-created [MediaPost] to the cache immediately (optimistic update).
  void addPost(MediaPost post) {
    final tag = post.eventTag ?? '_unsorted';
    _mergePost(tag, post);
  }

  // ── Cleanup ───────────────────────────────────────────────────────────────

  /// Disposes the repository: unsubscribes and closes the stream.
  Future<void> dispose() async {
    if (_globalSubId != null) {
      _nostr.unsubscribe(_globalSubId!);
      _globalSubId = null;
    }
    await _controller.close();
  }

  // ── Internal ──────────────────────────────────────────────────────────────

  void _handleNostrEvent(NostrEvent event) {
    final hashtag = event.getTagValue('t');
    if (hashtag == null) return;

    final post = _nostrEventToMediaPost(event, hashtag);
    _mergePost(hashtag, post);
  }

  void _mergePost(String hashtag, MediaPost post) {
    final existing = _cache[hashtag];

    if (existing == null) {
      _cache[hashtag] = CivicEvent(
        hashtag: hashtag,
        title: '#$hashtag',
        posts: [post],
        centerLat: post.latitude,
        centerLon: post.longitude,
        firstSeen: post.capturedAt,
        participantCount: 1,
      );
    } else {
      // Deduplicate by post ID
      final alreadyPresent =
          existing.posts.any((p) => p.id == post.id);
      if (alreadyPresent) return;

      final updatedPosts = [...existing.posts, post]
        ..sort((a, b) => a.capturedAt.compareTo(b.capturedAt));

      final uniquePubkeys =
          updatedPosts.map((p) => p.pubkey).toSet();

      // Recompute centre as average of GPS-tagged posts
      final geoTagged =
          updatedPosts.where((p) => p.hasGps).toList();
      double? lat, lon;
      if (geoTagged.isNotEmpty) {
        lat = geoTagged.map((p) => p.latitude!).reduce((a, b) => a + b) /
            geoTagged.length;
        lon = geoTagged.map((p) => p.longitude!).reduce((a, b) => a + b) /
            geoTagged.length;
      }

      _cache[hashtag] = existing.copyWith(
        posts: updatedPosts,
        centerLat: lat ?? existing.centerLat,
        centerLon: lon ?? existing.centerLon,
        participantCount: uniquePubkeys.length,
        firstSeen: updatedPosts.first.capturedAt,
      );
    }

    if (!_controller.isClosed) {
      _controller.add(_cache[hashtag]!);
    }
  }

  static MediaPost _nostrEventToMediaPost(
      NostrEvent event, String hashtag) {
    // geo tag format: ["geo", "lat", "lon"]
    double? latitude, longitude;
    for (final tag in event.tags) {
      if (tag.isNotEmpty && tag[0] == 'geo' && tag.length >= 3) {
        latitude = double.tryParse(tag[1]);
        longitude = double.tryParse(tag[2]);
        break;
      }
    }

    final contentHash =
        event.getTagValue('media_hash') ?? event.id;

    return MediaPost(
      id: event.id,
      pubkey: event.pubkey,
      contentHash: contentHash,
      latitude: latitude,
      longitude: longitude,
      capturedAt:
          DateTime.fromMillisecondsSinceEpoch(event.createdAt * 1000),
      eventTag: hashtag,
      isDangerMode: event.getTagValue('danger') == '1',
      tags: event.tags
          .where((t) => t.isNotEmpty)
          .map((t) => t.join(':'))
          .toList(),
      nostrEventId: event.id,
    );
  }
}

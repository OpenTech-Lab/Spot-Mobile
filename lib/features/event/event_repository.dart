import 'dart:async';

import 'package:mobile/features/nostr/nostr_models.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/cache_manager.dart';

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
        // kind-1: media posts (app-filtered)
        NostrFilter(
          kinds: [1],
          limit: 50,
          // #app filter tells the relay to send only Spot-originated events.
          // Relays that support multi-letter tag queries filter server-side;
          // others send more, and the client-side check below discards them.
          tags: {'app': ['spot']},
        ),
        // kind-5: revocation events (spec v1.4 §12 "Deletion Flow")
        // kind-1984: community reports (spec v1.4 §12.B)
        NostrFilter(kinds: [5, 1984], limit: 100, tags: {'app': ['spot']}),
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
    // Client-side guard: discard events not tagged as Spot-originated.
    if (event.getTagValue('app') != 'spot') return;

    switch (event.kind) {
      case 5:
        _handleRevocation(event);
      case 1984:
        _handleReport(event);
      default:
        _handleMediaPost(event);
    }
  }

  /// Spec v1.4 §12 "Deletion Flow" step 2: hide revoked content immediately.
  void _handleRevocation(NostrEvent event) {
    final contentHash = event.getTagValue('media_hash');
    if (contentHash != null) {
      CacheManager.instance.block(contentHash); // local block
      P2PService.instance.dropFromCache(contentHash); // drop swarm cache
      // Remove any in-memory posts matching this content hash
      for (final key in _cache.keys.toList()) {
        final civic = _cache[key]!;
        final updated =
            civic.posts.where((p) => p.contentHash != contentHash).toList();
        if (updated.length != civic.posts.length) {
          _cache[key] = civic.copyWith(
            posts: updated,
            participantCount:
                updated.map((p) => p.pubkey).toSet().length,
          );
          if (!_controller.isClosed) _controller.add(_cache[key]!);
        }
      }
    }
  }

  /// Spec v1.4 §12.B: propagate community reports to local blocklist.
  void _handleReport(NostrEvent event) {
    final contentHash = event.getTagValue('media_hash');
    if (contentHash != null) {
      CacheManager.instance.block(contentHash);
      P2PService.instance.dropFromCache(contentHash);
    }
  }

  void _handleMediaPost(NostrEvent event) {
    final contentHash = event.getTagValue('media_hash') ?? event.id;
    // Client-side blocklist filter (spec v1.4 §12.B)
    if (CacheManager.instance.isBlocked(contentHash)) return;

    final hashtag = event.getTagValue('t');
    // Posts without an event tag go into '_unsorted' so they still appear in
    // the feed — spec does not require a hashtag on every post.
    final bucket = hashtag ?? '_unsorted';
    final post = _nostrEventToMediaPost(event, hashtag);
    _mergePost(bucket, post);
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
      NostrEvent event, String? hashtag) {
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

    // Parse replyToId from ["e", ...] NIP-10 tag
    String? replyToId;
    for (final tag in event.tags) {
      if (tag.isNotEmpty && tag[0] == 'e' && tag.length >= 2) {
        replyToId = tag[1];
        break;
      }
    }

    // Parse caption: content minus the trailing #tag line
    String? caption;
    final rawContent = event.content.trim();
    if (rawContent.isNotEmpty) {
      final lines = rawContent.split('\n');
      final captionLines =
          lines.where((l) => !l.trim().startsWith('#')).toList();
      final joined = captionLines.join('\n').trim();
      if (joined.isNotEmpty) caption = joined;
    }

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
      caption: caption,
      replyToId: replyToId,
      tags: event.tags
          .where((t) => t.isNotEmpty)
          .map((t) => t.join(':'))
          .toList(),
      nostrEventId: event.id,
    );
  }
}

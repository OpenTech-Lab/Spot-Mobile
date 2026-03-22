import 'dart:async';

import 'package:mobile/features/ebes/trust_service.dart';
import 'package:mobile/features/nostr/nostr_models.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/witness_model.dart';
import 'package:mobile/services/cache_manager.dart';

/// Aggregates raw [NostrEvent]s from relays into [CivicEvent] domain objects.
///
/// The repository maintains an in-memory cache of [CivicEvent]s keyed by
/// hashtag.  Callers can stream live updates or query the current snapshot.
class EventRepository {
  EventRepository({required NostrService nostrService})
      : _nostr = nostrService;

  final NostrService _nostr;
  final _trust = const TrustService();

  /// In-memory cache: hashtag → CivicEvent
  final Map<String, CivicEvent> _cache = {};

  /// Broadcast stream of updated [CivicEvent]s.
  final _controller = StreamController<CivicEvent>.broadcast();

  String? _globalSubId;
  final List<String> _authorSubIds = [];

  /// Tracks post counts per pubkey for SourceScore computation.
  final Map<String, int> _postCountByPubkey = {};

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

  /// Subscribes to posts by a specific [authorPubkey] (e.g. for profile screen).
  /// Uses an author filter so the relay returns only that user's posts even on
  /// busy relays where a generic `limit: 50` would miss them.
  Stream<CivicEvent> subscribeToAuthorPosts(String authorPubkey) {
    final subId = _nostr.subscribe(
      [
        NostrFilter(
          kinds: [1],
          limit: 200,
          authors: [authorPubkey],
          tags: {'app': ['spot']},
        ),
        NostrFilter(kinds: [5, 1984], limit: 50, authors: [authorPubkey]),
      ],
      _handleNostrEvent,
    );
    _authorSubIds.add(subId);
    return _controller.stream;
  }

  /// Clears all cached events and unsubscribes from the relay so that the
  /// next [subscribeToEvents] / [subscribeToAuthorPosts] call issues a fresh
  /// REQ and the relay re-delivers stored events.
  void reset() {
    if (_globalSubId != null) {
      _nostr.unsubscribe(_globalSubId!);
      _globalSubId = null;
    }
    for (final id in _authorSubIds) {
      _nostr.unsubscribe(id);
    }
    _authorSubIds.clear();
    _cache.clear();
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
    for (final id in _authorSubIds) {
      _nostr.unsubscribe(id);
    }
    _authorSubIds.clear();
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
        // Check for witness signal before treating as a media post
        if (event.getTagValue('witness') != null) {
          _handleWitness(event);
        } else {
          _handleMediaPost(event);
        }
    }
  }

  /// Processes a witness signal event and updates the relevant [CivicEvent].
  void _handleWitness(NostrEvent event) {
    final hashtag = event.getTagValue('t');
    if (hashtag == null || !_cache.containsKey(hashtag)) return;

    final weight = _trust.witnessWeight(
      Witness.fromNostrEvent(event, weight: 0.5) ??
          Witness(
            id: event.id,
            eventId: hashtag,
            userId: event.pubkey,
            type: WitnessType.seen,
            timestamp: DateTime.fromMillisecondsSinceEpoch(
                event.createdAt * 1000),
            weight: 0.5,
          ),
      _cache[hashtag]!,
      postCountByPubkey: _postCountByPubkey,
    );

    final witness = Witness.fromNostrEvent(event, weight: weight);
    if (witness == null) return;

    final existing = _cache[hashtag]!;
    final alreadyPresent = existing.witnesses.any((w) => w.id == witness.id);
    if (alreadyPresent) return;

    final updatedWitnesses = [...existing.witnesses, witness];
    final updatedEvent =
        _applyTrust(existing.copyWith(witnesses: updatedWitnesses));
    _cache[hashtag] = updatedEvent;
    if (!_controller.isClosed) _controller.add(updatedEvent);
  }

  /// Spec v1.4 §12 "Deletion Flow" step 2: hide revoked content immediately.
  void _handleRevocation(NostrEvent event) {
    final hashes = event.getAllTagValues('media_hash');
    if (hashes.isEmpty) return;
    for (final hash in hashes) {
      CacheManager.instance.block(hash);
      P2PService.instance.dropFromCache(hash);
    }
    // Remove in-memory posts that share any revoked hash
    for (final key in _cache.keys.toList()) {
      final civic = _cache[key]!;
      final updated = civic.posts
          .where((p) => p.contentHashes.every((h) => !hashes.contains(h)))
          .toList();
      if (updated.length != civic.posts.length) {
        _cache[key] = civic.copyWith(
          posts: updated,
          participantCount: updated.map((p) => p.pubkey).toSet().length,
        );
        if (!_controller.isClosed) _controller.add(_cache[key]!);
      }
    }
  }

  /// Spec v1.4 §12.B: propagate community reports to local blocklist.
  void _handleReport(NostrEvent event) {
    for (final hash in event.getAllTagValues('media_hash')) {
      CacheManager.instance.block(hash);
      P2PService.instance.dropFromCache(hash);
    }
  }

  void _handleMediaPost(NostrEvent event) {
    final hashes = event.getAllTagValues('media_hash');
    if (hashes.isEmpty) hashes.add(event.id);
    // Client-side blocklist filter: drop if any file hash is blocked
    if (hashes.any(CacheManager.instance.isBlocked)) return;

    final hashtag = event.getTagValue('t');
    // Posts without an event tag go into '_unsorted' so they still appear in
    // the feed — spec does not require a hashtag on every post.
    final bucket = hashtag ?? '_unsorted';
    final post = _nostrEventToMediaPost(event, hashtag);
    _mergePost(bucket, post);
  }

  void _mergePost(String hashtag, MediaPost post) {
    // Track post count per pubkey for reputation scoring
    _postCountByPubkey[post.pubkey] =
        (_postCountByPubkey[post.pubkey] ?? 0) + 1;

    final existing = _cache[hashtag];

    if (existing == null) {
      final civic = CivicEvent(
        hashtag: hashtag,
        title: '#$hashtag',
        posts: [post],
        centerLat: post.latitude,
        centerLon: post.longitude,
        firstSeen: post.capturedAt,
        participantCount: 1,
      );
      _cache[hashtag] = _applyTrust(civic);
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

      final updated = existing.copyWith(
        posts: updatedPosts,
        centerLat: lat ?? existing.centerLat,
        centerLon: lon ?? existing.centerLon,
        participantCount: uniquePubkeys.length,
        firstSeen: updatedPosts.first.capturedAt,
      );
      _cache[hashtag] = _applyTrust(updated);
    }

    if (!_controller.isClosed) {
      _controller.add(_cache[hashtag]!);
    }
  }

  /// Recomputes [trustScore] and [status] on [event] using [TrustService].
  CivicEvent _applyTrust(CivicEvent event) {
    final score = _trust.computeEventTrust(
      event,
      event.witnesses,
      postCountByPubkey: _postCountByPubkey,
    );
    final status = _trust.statusFromScore(score, event.witnesses);
    return event.copyWith(trustScore: score, status: status);
  }

  /// Public static helper used by [FeedScreen] to convert raw Nostr events
  /// received via ad-hoc subscriptions into [MediaPost] objects.
  static MediaPost nostrEventToPost(NostrEvent event, String? hashtag) =>
      _nostrEventToMediaPost(event, hashtag);

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

    // Collect all media hashes (supports multi-file posts)
    final allHashes = event.getAllTagValues('media_hash');
    if (allHashes.isEmpty) allHashes.add(event.id);

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

    // Look up cached local paths for each hash
    final cachedPaths = allHashes
        .map((h) => CacheManager.instance.getCached(h)?.path)
        .whereType<String>()
        .toList();

    return MediaPost(
      id: event.id,
      pubkey: event.pubkey,
      contentHashes: allHashes,
      mediaPaths: cachedPaths,
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

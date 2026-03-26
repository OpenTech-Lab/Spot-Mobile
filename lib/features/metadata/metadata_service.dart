import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/features/metadata/metadata_post_mapper.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/models/witness_model.dart';

/// Supabase-backed metadata service for posts, events, reports, and witnesses.
///
/// The old Nostr wallet identity is still synced into `profiles.legacy_pubkey`
/// so the existing UI can keep using pubkey-shaped author identifiers while
/// metadata itself moves to Supabase.
class MetadataService {
  MetadataService._();

  static final MetadataService instance = MetadataService._();

  SupabaseClient get client => Supabase.instance.client;

  Future<User?> ensureSignedIn() async {
    final current = client.auth.currentUser;
    if (current != null) return current;

    final response = await client.auth.signInAnonymously();
    return response.user;
  }

  Future<void> syncLegacyProfile(WalletModel wallet) async {
    final user = await ensureSignedIn();
    if (user == null) {
      throw StateError('Unable to create a Supabase auth session');
    }

    await client.from('profiles').upsert({
      'id': user.id,
      'display_name': 'citizen-${wallet.publicKeyHex.substring(0, 8)}',
      'legacy_pubkey': wallet.publicKeyHex,
      'legacy_npub': wallet.npub,
      'device_id': wallet.deviceId,
      'avatar_seed': wallet.publicKeyHex.substring(0, 12),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');
  }

  Future<MediaPost> publishPost(MediaPost draft, WalletModel wallet) async {
    await syncLegacyProfile(wallet);

    for (final tag in draft.eventTags.toSet()) {
      await client.rpc(
        'ensure_event_exists',
        params: {
          'p_hashtag': tag,
          'p_title': '#$tag',
          'p_latitude': draft.latitude,
          'p_longitude': draft.longitude,
        },
      );
    }

    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }

    final inserted = await client
        .from('posts')
        .insert({...MetadataPostMapper.toInsertRow(draft), 'user_id': user.id})
        .select()
        .single();

    final mapped = (await mapPostRows([inserted])).single;
    return mapped.copyWith(
      mediaPaths: draft.mediaPaths,
      deliveryState: PostDeliveryState.sent,
      lastPublishError: null,
    );
  }

  Future<void> deletePost(
    String postId,
    String contentHash,
    WalletModel wallet,
  ) async {
    await syncLegacyProfile(wallet);
    await client
        .from('posts')
        .update({'deleted_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', postId);
  }

  Future<void> reportContent({
    required String postId,
    required String contentHash,
    required String reason,
    required WalletModel wallet,
  }) async {
    await syncLegacyProfile(wallet);
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }

    await client.from('content_reports').upsert({
      'post_id': postId,
      'content_hash': contentHash,
      'reporter_id': user.id,
      'reason': reason,
    }, onConflict: 'post_id,reporter_id');
  }

  Future<void> publishWitness({
    required String hashtag,
    required String witnessType,
    required WalletModel wallet,
    double? lat,
    double? lon,
  }) async {
    await syncLegacyProfile(wallet);
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }

    await client.rpc(
      'ensure_event_exists',
      params: {
        'p_hashtag': hashtag,
        'p_title': '#$hashtag',
        'p_latitude': lat,
        'p_longitude': lon,
      },
    );

    await client.from('witness_signals').upsert({
      'event_hashtag': hashtag,
      'user_id': user.id,
      'witness_type': witnessType,
      'latitude': lat,
      'longitude': lon,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'event_hashtag,user_id,witness_type');
  }

  Future<void> publishPeerEndpoints(
    List<Uri> endpoints,
    WalletModel wallet, {
    String protocol = 'spot-p2p-http-v1',
  }) async {
    await syncLegacyProfile(wallet);
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }

    await client.from('peer_endpoints').upsert({
      'user_id': user.id,
      'device_id': wallet.deviceId,
      'protocol': protocol,
      'endpoints': endpoints.map((endpoint) => endpoint.toString()).toList(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<void> clearPeerEndpoints(WalletModel wallet) async {
    await syncLegacyProfile(wallet);
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }

    await client.from('peer_endpoints').upsert({
      'user_id': user.id,
      'device_id': wallet.deviceId,
      'protocol': 'spot-p2p-http-v1',
      'endpoints': <String>[],
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id');
  }

  Future<List<Uri>> resolvePeerEndpoints(String authorPubkey) async {
    final authorIds = await resolveAuthorIds(authorPubkey);
    if (authorIds.isEmpty) return const [];

    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('peer_endpoints')
          .select('endpoints')
          .inFilter('user_id', authorIds),
    );

    final endpoints = <Uri>[];
    for (final row in rows) {
      final rawEndpoints = row['endpoints'];
      if (rawEndpoints is! List) continue;
      for (final raw in rawEndpoints) {
        final parsed = Uri.tryParse(raw.toString());
        if (parsed != null &&
            parsed.hasScheme &&
            parsed.host.isNotEmpty &&
            !endpoints.contains(parsed)) {
          endpoints.add(parsed);
        }
      }
    }

    return endpoints;
  }

  Future<List<MediaPost>> fetchPosts({
    String? authorPubkey,
    String? hashtag,
    DateTime? before,
    int limit = 20,
  }) async {
    List<String>? authorIds;
    if (authorPubkey != null) {
      authorIds = await resolveAuthorIds(authorPubkey);
      if (authorIds.isEmpty) return const [];
    }

    dynamic query = client
        .from('posts')
        .select()
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(limit);

    if (before != null) {
      query = query.lt('created_at', before.toUtc().toIso8601String());
    }
    if (hashtag != null && hashtag.isNotEmpty) {
      query = query.eq('event_hashtag', hashtag);
    }
    if (authorIds != null && authorIds.isNotEmpty) {
      query = query.inFilter('user_id', authorIds);
    }

    final rows = List<Map<String, dynamic>>.from(await query);
    return mapPostRows(rows);
  }

  Future<List<Witness>> fetchWitnesses(Iterable<String> hashtags) async {
    final uniqueHashtags = hashtags
        .where((tag) => tag.isNotEmpty)
        .toSet()
        .toList();
    if (uniqueHashtags.isEmpty) return const [];

    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('witness_signals')
          .select()
          .inFilter('event_hashtag', uniqueHashtags)
          .order('created_at', ascending: false),
    );

    return mapWitnessRows(rows);
  }

  Future<Set<String>> fetchBlockedHashes(Iterable<String> hashes) async {
    final uniqueHashes = hashes
        .where((hash) => hash.isNotEmpty)
        .toSet()
        .toList();
    if (uniqueHashes.isEmpty) return const <String>{};

    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('blocklist')
          .select('content_hash')
          .inFilter('content_hash', uniqueHashes),
    );

    return rows
        .map((row) => row['content_hash']?.toString())
        .whereType<String>()
        .toSet();
  }

  Future<List<String>> resolveAuthorIds(String authorPubkey) async {
    final value = authorPubkey.trim();
    if (value.isEmpty) return const [];

    final rows = List<Map<String, dynamic>>.from(
      await client.from('profiles').select('id').eq('legacy_pubkey', value),
    );

    final ids = rows
        .map((row) => row['id']?.toString())
        .whereType<String>()
        .toSet();
    if (ids.isNotEmpty) return ids.toList(growable: false);

    final uuidLike = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$',
    );
    if (uuidLike.hasMatch(value)) {
      return [value];
    }

    return const [];
  }

  Future<List<MediaPost>> mapPostRows(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return const [];

    final userIds = rows
        .map((row) => row['user_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final profileMap = await _loadProfiles(userIds);
    final posts = rows
        .map((row) {
          final userId = row['user_id']?.toString() ?? '';
          final profile = profileMap[userId];
          final authorKey = profile?['legacy_pubkey']?.toString();
          return MetadataPostMapper.fromRow(
            row,
            authorKey: authorKey?.isNotEmpty == true ? authorKey! : userId,
          );
        })
        .toList(growable: false);

    final blocked = await fetchBlockedHashes(
      posts.expand((post) => post.contentHashes),
    );

    return posts
        .where(
          (post) => post.contentHashes.every((hash) => !blocked.contains(hash)),
        )
        .toList(growable: false);
  }

  Future<List<Witness>> mapWitnessRows(List<Map<String, dynamic>> rows) async {
    if (rows.isEmpty) return const [];

    final userIds = rows
        .map((row) => row['user_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final profileMap = await _loadProfiles(userIds);
    final witnesses = <Witness>[];

    for (final row in rows) {
      final userId = row['user_id']?.toString() ?? '';
      final witness = Witness.fromSupabaseRow(
        row,
        fallbackUserId: userId,
        legacyPubkey: profileMap[userId]?['legacy_pubkey']?.toString(),
      );
      if (witness != null) {
        witnesses.add(witness);
      }
    }

    return witnesses;
  }

  Future<Map<String, Map<String, dynamic>>> _loadProfiles(
    List<String> userIds,
  ) async {
    if (userIds.isEmpty) return const {};

    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('profiles')
          .select('id, legacy_pubkey, legacy_npub, display_name')
          .inFilter('id', userIds),
    );

    return {
      for (final row in rows)
        if (row['id'] != null) row['id'].toString(): row,
    };
  }
}

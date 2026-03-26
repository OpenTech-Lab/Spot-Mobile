import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/tag_normalizer.dart';
import 'package:mobile/features/metadata/metadata_post_mapper.dart';
import 'package:mobile/models/follow_stats.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/models/witness_model.dart';

bool isDeleteAlreadyGoneError(PostgrestException error) {
  final message = error.message.trim().toLowerCase();
  return error.code == 'P0001' && message == 'post not found for deletion';
}

Map<String, dynamic> buildSoftDeletePostParams({
  required String requestedPostId,
  required String contentHash,
}) {
  final params = <String, dynamic>{};
  final normalizedPostId = requestedPostId.trim();
  final normalizedHash = contentHash.trim();
  if (normalizedPostId.isNotEmpty) {
    params['p_requested_post_id'] = normalizedPostId;
  }
  if (normalizedHash.isNotEmpty) {
    params['p_content_hash'] = normalizedHash;
  }
  return params;
}

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

    try {
      final response = await client.auth.signInAnonymously();
      return response.user;
    } on AuthException catch (error) {
      debugPrint(
        '[MetadataService] Anonymous sign-in failed: ${error.message}',
      );
      throw StateError(
        'Supabase anonymous sign-in failed. Enable Anonymous Auth and verify '
        'SUPABASE_URL/SUPABASE_ANON_KEY. ${error.message}',
      );
    }
  }

  Future<void> syncLegacyProfile(WalletModel wallet) async {
    final user = await ensureSignedIn();
    if (user == null) {
      throw StateError('Unable to create a Supabase auth session');
    }
    final existingProfile = await _fetchProfileById(user.id);
    final displayName = existingProfile?.displayName?.trim().isNotEmpty == true
        ? existingProfile!.displayName!.trim()
        : _defaultDisplayNameForWallet(wallet);
    final avatarSeed = existingProfile?.avatarSeed?.trim().isNotEmpty == true
        ? existingProfile!.avatarSeed!.trim()
        : wallet.publicKeyHex.substring(0, 12);

    debugPrint('[MetadataService] Syncing profile for ${user.id}');
    try {
      await client.from('profiles').upsert({
        'id': user.id,
        'display_name': displayName,
        'legacy_pubkey': wallet.publicKeyHex,
        'legacy_npub': wallet.npub,
        'device_id': wallet.deviceId,
        'avatar_seed': avatarSeed,
        'avatar_content_hash': existingProfile?.avatarContentHash,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'id');
      debugPrint('[MetadataService] Profile sync complete for ${user.id}');
    } on PostgrestException catch (error, stackTrace) {
      debugPrint(
        '[MetadataService] Profile sync failed for ${user.id}: '
        'message=${error.message} code=${error.code} '
        'details=${error.details} hint=${error.hint}',
      );
      debugPrintStack(
        label: '[MetadataService] Profile sync stack for ${user.id}',
        stackTrace: stackTrace,
      );
      throw StateError(
        'Supabase profile sync failed. Check profiles table/RLS setup. '
        '${error.message}'
        '${error.details != null ? ' details=${error.details}' : ''}'
        '${error.hint != null ? ' hint=${error.hint}' : ''}',
      );
    }
  }

  Future<ProfileModel> fetchCurrentProfile(WalletModel wallet) async {
    await syncLegacyProfile(wallet);
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }
    final profile = await _fetchProfileById(user.id);
    if (profile == null) {
      throw StateError('Supabase profile row missing after sync');
    }
    return profile;
  }

  Future<ProfileModel?> fetchProfileByPubkey(String pubkey) async {
    final authorIds = await resolveAuthorIds(pubkey);
    if (authorIds.isEmpty) return null;

    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('profiles')
          .select(
            'id, display_name, legacy_pubkey, legacy_npub, device_id, '
            'avatar_seed, avatar_content_hash',
          )
          .inFilter('id', authorIds)
          .limit(1),
    );
    if (rows.isEmpty) return null;
    return ProfileModel.fromRow(rows.first);
  }

  Future<ProfileModel> updateCurrentProfile({
    required WalletModel wallet,
    required String displayName,
    String? avatarContentHash,
  }) async {
    await syncLegacyProfile(wallet);
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }

    final normalizedDisplayName = displayName.trim().isNotEmpty
        ? displayName.trim()
        : _defaultDisplayNameForWallet(wallet);
    final existingProfile = await _fetchProfileById(user.id);

    await client.from('profiles').upsert({
      'id': user.id,
      'display_name': normalizedDisplayName,
      'legacy_pubkey': wallet.publicKeyHex,
      'legacy_npub': wallet.npub,
      'device_id': wallet.deviceId,
      'avatar_seed': existingProfile?.avatarSeed?.trim().isNotEmpty == true
          ? existingProfile!.avatarSeed!.trim()
          : wallet.publicKeyHex.substring(0, 12),
      'avatar_content_hash':
          avatarContentHash ?? existingProfile?.avatarContentHash,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'id');

    final updatedProfile = await _fetchProfileById(user.id);
    if (updatedProfile == null) {
      throw StateError('Supabase profile row missing after update');
    }
    return updatedProfile;
  }

  Future<void> deleteCurrentAccount() async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError(
        'Missing Supabase session for account deletion. Restart the app and try again.',
      );
    }

    await client.from('profiles').delete().eq('id', user.id);
    await client.auth.signOut();
  }

  Future<FollowStats> fetchCurrentFollowStats(WalletModel wallet) async {
    await syncLegacyProfile(wallet);
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }
    return fetchFollowStatsForProfileId(user.id);
  }

  Future<FollowStats?> fetchFollowStatsByPubkey(String pubkey) async {
    final authorIds = await resolveAuthorIds(pubkey);
    if (authorIds.isEmpty) return null;
    return fetchFollowStatsForProfileId(authorIds.first);
  }

  Future<FollowStats> fetchFollowStatsForProfileId(String profileId) async {
    try {
      final response = await client.rpc(
        'get_follow_stats',
        params: {'p_profile_id': profileId},
      );

      if (response is List && response.isNotEmpty && response.first is Map) {
        return FollowStats.fromRpcRow(
          Map<String, dynamic>.from(response.first as Map),
        );
      }
      if (response is Map) {
        return FollowStats.fromRpcRow(Map<String, dynamic>.from(response));
      }
    } catch (e) {
      debugPrint('[MetadataService] Failed to fetch follow stats: $e');
    }
    return const FollowStats.empty();
  }

  Future<FollowStats> setFollowingForPubkey({
    required String targetPubkey,
    required bool shouldFollow,
    required WalletModel wallet,
  }) async {
    await syncLegacyProfile(wallet);
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }

    final authorIds = await resolveAuthorIds(targetPubkey);
    if (authorIds.isEmpty) {
      throw StateError('Target profile is unavailable for follow actions');
    }

    final targetProfileId = authorIds.first;
    if (targetProfileId == user.id) {
      return fetchFollowStatsForProfileId(targetProfileId);
    }

    if (shouldFollow) {
      await client.from('follows').upsert({
        'follower_id': user.id,
        'followed_profile_id': targetProfileId,
      }, onConflict: 'follower_id,followed_profile_id');
    } else {
      await client
          .from('follows')
          .delete()
          .eq('follower_id', user.id)
          .eq('followed_profile_id', targetProfileId);
    }

    return fetchFollowStatsForProfileId(targetProfileId);
  }

  Future<MediaPost> publishPost(MediaPost draft, WalletModel wallet) async {
    final normalizedDraft = draft.copyWith(
      eventTags: normalizeUniqueTags(draft.eventTags),
    );
    await syncLegacyProfile(wallet);

    for (final tag in normalizedDraft.eventTags.toSet()) {
      await client.rpc(
        'ensure_event_exists',
        params: {
          'p_hashtag': tag,
          'p_title': '#$tag',
          'p_latitude': normalizedDraft.latitude,
          'p_longitude': normalizedDraft.longitude,
        },
      );
    }

    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }

    final inserted = await client
        .from('posts')
        .insert({
          ...MetadataPostMapper.toInsertRow(normalizedDraft),
          'user_id': user.id,
        })
        .select()
        .single();

    final mapped = (await mapPostRows([inserted])).single;
    return mapped.copyWith(
      mediaPaths: normalizedDraft.mediaPaths,
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
    try {
      await client.rpc(
        'soft_delete_post',
        params: buildSoftDeletePostParams(
          requestedPostId: postId,
          contentHash: contentHash,
        ),
      );
    } on PostgrestException catch (error) {
      if (isDeleteAlreadyGoneError(error)) {
        debugPrint('[MetadataService] Delete already applied for $postId');
        return;
      }
      rethrow;
    }
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
    final normalizedHashtag = normalizeTag(hashtag);
    if (normalizedHashtag.isEmpty) {
      throw StateError('Witness hashtag is required');
    }
    await syncLegacyProfile(wallet);
    final user = client.auth.currentUser;
    if (user == null) {
      throw StateError('Missing Supabase user after profile sync');
    }

    await client.rpc(
      'ensure_event_exists',
      params: {
        'p_hashtag': normalizedHashtag,
        'p_title': '#$normalizedHashtag',
        'p_latitude': lat,
        'p_longitude': lon,
      },
    );

    await client.rpc(
      'set_witness_signal',
      params: {
        'p_event_hashtag': normalizedHashtag,
        'p_witness_type': witnessType,
        'p_latitude': lat,
        'p_longitude': lon,
      },
    );
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
          .select(
            'id, legacy_pubkey, legacy_npub, display_name, avatar_seed, '
            'avatar_content_hash',
          )
          .inFilter('id', userIds),
    );

    return {
      for (final row in rows)
        if (row['id'] != null) row['id'].toString(): row,
    };
  }

  Future<ProfileModel?> _fetchProfileById(String userId) async {
    final rows = List<Map<String, dynamic>>.from(
      await client
          .from('profiles')
          .select(
            'id, display_name, legacy_pubkey, legacy_npub, device_id, '
            'avatar_seed, avatar_content_hash',
          )
          .eq('id', userId)
          .limit(1),
    );
    if (rows.isEmpty) return null;
    return ProfileModel.fromRow(rows.first);
  }

  String _defaultDisplayNameForWallet(WalletModel wallet) =>
      'citizen-${wallet.publicKeyHex.substring(0, 8)}';
}

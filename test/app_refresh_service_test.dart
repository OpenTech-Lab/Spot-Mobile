import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/services/app_refresh_service.dart';

void main() {
  test(
    'refreshSessionData fetches, dedupes, saves posts, and updates profile',
    () async {
      final fetchCalls = <({String? authorPubkey, int limit})>[];
      final savedPostIds = <String>[];
      String? updatedAuthorPubkey;
      String? updatedDisplayName;
      String? updatedAvatarHash;
      var initFollowStateCalls = 0;

      final service = AppRefreshService(
        initFollowState: () async => initFollowStateCalls++,
        fetchCurrentProfile: (_) async => const ProfileModel(
          id: 'profile-id',
          displayName: '  Alice  ',
          avatarContentHash: 'avatar-hash',
        ),
        fetchPosts: ({authorPubkey, limit = 20}) async {
          fetchCalls.add((authorPubkey: authorPubkey, limit: limit));
          if (authorPubkey == null) {
            return [
              _post(id: 'recent-a', pubkey: 'author-a'),
              _post(id: 'shared', pubkey: 'self-pubkey'),
            ];
          }
          return [
            _post(id: 'shared', pubkey: authorPubkey),
            _post(id: 'mine-only', pubkey: authorPubkey),
          ];
        },
        savePosts: (posts) async {
          savedPostIds
            ..clear()
            ..addAll(posts.map((post) => post.id));
        },
        updateAuthorProfile:
            ({required authorPubkey, displayName, avatarContentHash}) async {
              updatedAuthorPubkey = authorPubkey;
              updatedDisplayName = displayName;
              updatedAvatarHash = avatarContentHash;
            },
      );

      await service.refreshSessionData(
        _wallet(),
        recentLimit: 50,
        authorLimit: 25,
      );

      expect(initFollowStateCalls, 1);
      expect(fetchCalls, [
        (authorPubkey: null, limit: 50),
        (authorPubkey: 'self-pubkey', limit: 25),
      ]);
      expect(savedPostIds, ['recent-a', 'shared', 'mine-only']);
      expect(updatedAuthorPubkey, 'self-pubkey');
      expect(updatedDisplayName, 'Alice');
      expect(updatedAvatarHash, 'avatar-hash');
    },
  );
}

WalletModel _wallet() => WalletModel(
  privateKeyHex:
      '0000000000000000000000000000000000000000000000000000000000000001',
  publicKeyHex: 'self-pubkey',
  npub: 'npub1test',
  mnemonic: const ['test'],
  deviceId: 'device-1',
  isRevoked: false,
  createdAt: DateTime.utc(2026, 3, 29),
);

MediaPost _post({required String id, required String pubkey}) => MediaPost(
  id: id,
  pubkey: pubkey,
  contentHashes: [id],
  capturedAt: DateTime.utc(2026, 3, 29),
  eventTags: const ['tokyo'],
  nostrEventId: id,
);

import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/services/local_post_store.dart';

typedef SessionProfileFetcher =
    Future<ProfileModel> Function(WalletModel wallet);
typedef SessionPostsFetcher =
    Future<List<MediaPost>> Function({String? authorPubkey, int limit});
typedef SessionPostSaver = Future<void> Function(Iterable<MediaPost> posts);
typedef SessionAuthorProfileUpdater =
    Future<void> Function({
      required String authorPubkey,
      String? displayName,
      String? avatarContentHash,
    });
typedef SessionFollowStateInitializer = Future<void> Function();

class AppRefreshService {
  AppRefreshService({
    SessionProfileFetcher? fetchCurrentProfile,
    SessionPostsFetcher? fetchPosts,
    SessionPostSaver? savePosts,
    SessionAuthorProfileUpdater? updateAuthorProfile,
    SessionFollowStateInitializer? initFollowState,
  }) : _fetchCurrentProfile =
           fetchCurrentProfile ?? MetadataService.instance.fetchCurrentProfile,
       _fetchPosts = fetchPosts ?? MetadataService.instance.fetchPosts,
       _savePosts = savePosts ?? LocalPostStore.instance.savePosts,
       _updateAuthorProfile =
           updateAuthorProfile ?? LocalPostStore.instance.updateAuthorProfile,
       _initFollowState = initFollowState ?? FollowService.instance.init;

  static final AppRefreshService instance = AppRefreshService();

  final SessionProfileFetcher _fetchCurrentProfile;
  final SessionPostsFetcher _fetchPosts;
  final SessionPostSaver _savePosts;
  final SessionAuthorProfileUpdater _updateAuthorProfile;
  final SessionFollowStateInitializer _initFollowState;

  Future<void> refreshSessionData(
    WalletModel wallet, {
    int recentLimit = 200,
    int authorLimit = 200,
  }) async {
    await _initFollowState();

    final profile = await _fetchCurrentProfile(wallet);
    final recentPosts = await _fetchPosts(limit: recentLimit);
    final authorPosts = await _fetchPosts(
      authorPubkey: wallet.publicKeyHex,
      limit: authorLimit,
    );

    await _savePosts(_dedupePosts([...recentPosts, ...authorPosts]));
    await _updateAuthorProfile(
      authorPubkey: wallet.publicKeyHex,
      displayName: _normalizedDisplayName(profile),
      avatarContentHash: profile.avatarContentHash,
    );
  }

  List<MediaPost> _dedupePosts(Iterable<MediaPost> posts) {
    final byId = <String, MediaPost>{};
    for (final post in posts) {
      byId[post.id] = post;
    }
    return byId.values.toList(growable: false);
  }

  String? _normalizedDisplayName(ProfileModel profile) {
    final displayName = profile.displayName?.trim();
    if (displayName == null || displayName.isEmpty) return null;
    return displayName;
  }
}

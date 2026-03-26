import 'package:flutter/foundation.dart';

import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/services/local_post_store.dart';

/// Shared publish/persist helper for new posts and retrying failed local posts.
class PostPublishService {
  PostPublishService._();

  static final PostPublishService instance = PostPublishService._();

  Future<MediaPost> publishDraft({
    required MediaPost draft,
    required WalletModel wallet,
    EventRepository? eventRepo,
    String? replaceLocalPostId,
  }) async {
    debugPrint('[PostPublish] Starting publish for ${draft.id}');
    debugPrint(
      '[PostPublish] eventRepo is ${eventRepo == null ? "NULL" : "present"}',
    );

    final published = await MetadataService.instance.publishPost(draft, wallet);

    if (replaceLocalPostId != null) {
      await LocalPostStore.instance.replacePost(replaceLocalPostId, published);
      debugPrint(
        '[PostPublish] Replaced local post $replaceLocalPostId with ${published.id}',
      );
    } else {
      await LocalPostStore.instance.savePost(published);
      debugPrint('[PostPublish] Saved to LocalPostStore: ${published.id}');
    }

    if (eventRepo != null) {
      eventRepo.addPost(published);
      debugPrint(
        '[PostPublish] Added to EventRepository: ${published.id}, tags: ${published.eventTags}',
      );
    } else {
      debugPrint(
        '[PostPublish] WARNING: eventRepo is null, post will not appear in feed!',
      );
    }

    for (var i = 0; i < draft.contentHashes.length; i++) {
      if (i >= draft.mediaPaths.length) break;
      await P2PService.instance.seedMedia(
        draft.mediaPaths[i],
        draft.contentHashes[i],
      );
    }

    debugPrint('[PostPublish] Publish complete for ${published.id}');
    return published;
  }

  Future<MediaPost> saveFailedPublish(MediaPost draft, Object error) async {
    final failed = draft.copyWith(
      deliveryState: PostDeliveryState.failedToSend,
      lastPublishError: error.toString(),
    );
    await LocalPostStore.instance.savePost(failed);
    return failed;
  }
}

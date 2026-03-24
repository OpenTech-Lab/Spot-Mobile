import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
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
    required NostrService nostrService,
    EventRepository? eventRepo,
    String? replaceLocalPostId,
  }) async {
    final signed = await nostrService.publishMediaPost(draft, wallet);
    final published = draft.copyWith(
      id: signed.id,
      nostrEventId: signed.id,
      contentHashes: draft.isTextOnly ? [signed.id] : draft.contentHashes,
      capturedAt: DateTime.fromMillisecondsSinceEpoch(signed.createdAt * 1000),
      deliveryState: PostDeliveryState.sent,
      lastPublishError: null,
    );

    if (replaceLocalPostId != null) {
      await LocalPostStore.instance.replacePost(replaceLocalPostId, published);
    } else {
      await LocalPostStore.instance.savePost(published);
    }

    eventRepo?.addPost(published);

    for (var i = 0; i < draft.contentHashes.length; i++) {
      if (i >= draft.mediaPaths.length) break;
      await P2PService.instance.seedMedia(
        draft.mediaPaths[i],
        draft.contentHashes[i],
      );
    }

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

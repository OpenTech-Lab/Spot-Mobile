import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:mobile/core/tag_normalizer.dart';
import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/services/local_post_store.dart';

const String kMissingCategoryTagMessage =
    'Add a category tag before posting a new thread.';

String? validateThreadCategoryRequirement({
  required String? replyToId,
  required Iterable<String> eventTags,
}) {
  if (replyToId != null) return null;
  if (normalizeUniqueTags(eventTags).isNotEmpty) return null;
  return kMissingCategoryTagMessage;
}

String? validateDraftForPublish(MediaPost draft) =>
    validateThreadCategoryRequirement(
      replyToId: draft.replyToId,
      eventTags: draft.eventTags,
    );

class MissingCategoryTagError implements Exception {
  const MissingCategoryTagError([this.message = kMissingCategoryTagMessage]);

  final String message;

  @override
  String toString() => message;
}

class PublishDeniedError implements Exception {
  const PublishDeniedError({required this.code, required this.message});

  final String code;
  final String message;

  @override
  String toString() => message;
}

const Map<String, String> _publishDeniedFallbackMessages = {
  'POSTING_BLOCKED':
      'This account is blocked from publishing due to spam or bot-like activity.',
  'THREAD_DAILY_LIMIT_REACHED': 'Daily thread limit reached.',
  'REPLY_DAILY_LIMIT_REACHED': 'Daily reply limit reached.',
  'REPLY_TARGET_NOT_FOUND': 'The post you are replying to is unavailable.',
};

Object normalizePublishError(Object error) {
  if (error is MissingCategoryTagError || error is PublishDeniedError) {
    return error;
  }
  if (error is! PostgrestException) return error;

  final code = error.details?.toString().trim();
  if (code == null || code.isEmpty) return error;

  if (code == 'MISSING_CATEGORY_TAG') {
    return MissingCategoryTagError(_publishErrorMessage(error, code));
  }

  if (!_publishDeniedFallbackMessages.containsKey(code)) {
    return error;
  }

  return PublishDeniedError(
    code: code,
    message: _publishErrorMessage(error, code),
  );
}

String _publishErrorMessage(PostgrestException error, String code) {
  final hint = error.hint?.trim();
  if (hint != null && hint.isNotEmpty) return hint;
  return _publishDeniedFallbackMessages[code] ?? error.message;
}

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
    final validationMessage = validateDraftForPublish(draft);
    if (validationMessage != null) {
      throw MissingCategoryTagError(validationMessage);
    }

    debugPrint('[PostPublish] Starting publish for ${draft.id}');
    debugPrint(
      '[PostPublish] eventRepo is ${eventRepo == null ? "NULL" : "present"}',
    );

    try {
      final published = await MetadataService.instance.publishPost(
        draft,
        wallet,
      );

      if (replaceLocalPostId != null) {
        await LocalPostStore.instance.replacePost(
          replaceLocalPostId,
          published,
        );
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
    } catch (error, stackTrace) {
      final normalizedError = normalizePublishError(error);
      debugPrint('[PostPublish] Failed for ${draft.id}: $normalizedError');
      debugPrintStack(
        label: '[PostPublish] Stack for ${draft.id}',
        stackTrace: stackTrace,
      );
      Error.throwWithStackTrace(normalizedError, stackTrace);
    }
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

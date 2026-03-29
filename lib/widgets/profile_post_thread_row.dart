import 'package:flutter/widgets.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/widgets/post_thread_row.dart';

class ProfilePostThreadRow extends StatelessWidget {
  const ProfilePostThreadRow({
    super.key,
    required this.post,
    this.isLast = true,
    this.onAvatarTap,
    this.onTagTap,
    this.onReply,
    this.onLike,
    this.onDelete,
    this.onReport,
    this.onRetryPublish,
    this.isRetrying = false,
    this.isMediaLoading = false,
    this.onMediaUpdated,
  });

  final MediaPost post;
  final bool isLast;
  final VoidCallback? onAvatarTap;
  final ValueChanged<String>? onTagTap;
  final VoidCallback? onReply;
  final VoidCallback? onLike;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;
  final VoidCallback? onRetryPublish;
  final bool isRetrying;
  final bool isMediaLoading;
  final ValueChanged<MediaPost>? onMediaUpdated;

  @override
  Widget build(BuildContext context) {
    return PostThreadRow(
      post: post,
      isLast: isLast,
      useFeedEdgeSwipeMediaLayout: true,
      onAvatarTap: onAvatarTap,
      onTagTap: onTagTap,
      onReply: onReply,
      onLike: onLike,
      onDelete: onDelete,
      onReport: onReport,
      onRetryPublish: onRetryPublish,
      isRetrying: isRetrying,
      isMediaLoading: isMediaLoading,
      onMediaUpdated: onMediaUpdated,
    );
  }
}

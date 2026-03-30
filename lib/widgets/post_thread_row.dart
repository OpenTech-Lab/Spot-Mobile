import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile/core/post_location_formatter.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/screens/media_detail_screen.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/profile_avatar.dart';

const double postThreadRowHorizontalPadding = SpotSpacing.lg;
const double postThreadRowLeadingColumnWidth = 44;
const double postThreadRowLeadingGap = SpotSpacing.sm;
const double postThreadRowFeedMediaSwipeLeftBleed =
    postThreadRowHorizontalPadding +
    postThreadRowLeadingColumnWidth +
    postThreadRowLeadingGap;
const double postThreadRowFeedMediaSwipeActivationThreshold = 6;
const double postThreadRowMediaGap = 6;
const ValueKey<String> postThreadRowMediaViewportKey = ValueKey<String>(
  'post-thread-row-media-viewport',
);
const ValueKey<String> postThreadRowMediaContentKey = ValueKey<String>(
  'post-thread-row-media-content',
);

double postThreadRowFeedTwoImageWidth(double viewportWidth) {
  final minimumWidth =
      (viewportWidth +
          (postThreadRowFeedMediaSwipeLeftBleed * 2) +
          postThreadRowFeedMediaSwipeActivationThreshold -
          postThreadRowMediaGap) /
      2;
  if (minimumWidth < 200) return 200;
  return minimumWidth;
}

List<String> visibleThreadTagsForPost(MediaPost post) {
  if (post.eventTags.isEmpty) return const [];
  if (post.eventTags.length == 1) return const [];
  return post.eventTags.sublist(1);
}

String visibleThreadLocationTextForPost(
  MediaPost post, {
  GeoLocation? geoLocation,
}) {
  return visiblePostLocationText(
    isVirtual: post.isVirtual,
    latitude: post.latitude,
    longitude: post.longitude,
    geoLocation: geoLocation ?? _geoLocationForPost(post),
    spotName: post.spotName,
  );
}

/// Twitter/Threads-style thread row for a single [MediaPost].
///
/// Set [isLast] to true on the final row to suppress the connector line.
class PostThreadRow extends StatelessWidget {
  const PostThreadRow({
    super.key,
    required this.post,
    required this.isLast,
    this.useFeedEdgeSwipeMediaLayout = false,
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
  final bool useFeedEdgeSwipeMediaLayout;
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

  void _showPostMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(SpotRadius.lg),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SpotSpacing.lg,
            vertical: SpotSpacing.md,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: SpotSpacing.lg),
                decoration: BoxDecoration(
                  color: SpotColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              // Delete option (own posts only)
              if (onDelete != null)
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.delete,
                    color: SpotColors.danger,
                    size: 20,
                  ),
                  title: const Text(
                    'Delete post',
                    style: TextStyle(color: SpotColors.danger),
                  ),
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onDelete?.call();
                  },
                ),
              // Report option (all posts)
              if (onReport != null)
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.flag,
                    color: SpotColors.warning,
                    size: 20,
                  ),
                  title: const Text(
                    'Report content',
                    style: TextStyle(color: SpotColors.warning),
                  ),
                  contentPadding: EdgeInsets.zero,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    onReport?.call();
                  },
                ),
              // Cancel option
              ListTile(
                leading: const Icon(
                  CupertinoIcons.xmark,
                  color: SpotColors.textSecondary,
                  size: 20,
                ),
                title: const Text(
                  'Cancel',
                  style: TextStyle(color: SpotColors.textSecondary),
                ),
                contentPadding: EdgeInsets.zero,
                onTap: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleTags = visibleThreadTagsForPost(post);
    final headerCategoryTag = post.eventTag;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        postThreadRowHorizontalPadding,
        SpotSpacing.sm,
        postThreadRowHorizontalPadding,
        0,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Left: avatar + thread connector line ────────────────────────
            SizedBox(
              width: postThreadRowLeadingColumnWidth,
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: onAvatarTap,
                    behavior: HitTestBehavior.opaque,
                    child: ProfileAvatar(
                      pubkey: post.pubkey,
                      avatarContentHash: post.authorAvatarContentHash,
                      size: 36,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 1.5,
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          color: SpotColors.border,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: postThreadRowLeadingGap),
            // ── Right: post content ──────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: isLast ? SpotSpacing.md : SpotSpacing.xl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Author + timestamp + menu
                    Row(
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: SpotSpacing.xs,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                _authorDisplayNameForPost(post),
                                style: SpotType.bodySecondary,
                              ),
                              if (headerCategoryTag != null)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 96,
                                  ),
                                  child: GestureDetector(
                                    onTap: onTagTap == null
                                        ? null
                                        : () => onTagTap!(headerCategoryTag),
                                    behavior: HitTestBehavior.opaque,
                                    child: Text(
                                      '#$headerCategoryTag',
                                      style: SpotType.caption.copyWith(
                                        color: SpotColors.accent,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ),
                              Text(
                                '· ${_relativeTime(post.capturedAt)}',
                                style: SpotType.caption,
                              ),
                            ],
                          ),
                        ),
                        if (post.isDangerMode) ...[
                          const SizedBox(width: SpotSpacing.sm),
                          _PostBadge(
                            label: 'Protected',
                            color: SpotColors.danger,
                            bg: SpotColors.dangerSubtle,
                          ),
                        ],
                        if (post.isAiGenerated) ...[
                          const SizedBox(width: SpotSpacing.sm),
                          _PostBadge(
                            label: 'AI',
                            color: SpotColors.warning,
                            bg: SpotColors.warningSubtle,
                          ),
                        ],
                        if (post.isPendingRetry) ...[
                          const SizedBox(width: SpotSpacing.sm),
                          _PostBadge(
                            label: 'Not sent',
                            color: SpotColors.warning,
                            bg: SpotColors.warningSubtle,
                          ),
                        ],
                        if (onRetryPublish != null) ...[
                          const SizedBox(width: SpotSpacing.sm),
                          GestureDetector(
                            onTap: isRetrying ? null : onRetryPublish,
                            behavior: HitTestBehavior.opaque,
                            child: Padding(
                              padding: const EdgeInsets.all(2),
                              child: isRetrying
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: SpotColors.warning,
                                      ),
                                    )
                                  : const Icon(
                                      CupertinoIcons.refresh,
                                      size: 16,
                                      color: SpotColors.warning,
                                    ),
                            ),
                          ),
                        ],
                        if (onDelete != null || onReport != null) ...[
                          const Spacer(),
                          GestureDetector(
                            onTap: () => _showPostMenu(context),
                            behavior: HitTestBehavior.opaque,
                            child: const Padding(
                              padding: EdgeInsets.only(left: SpotSpacing.sm),
                              child: Icon(
                                CupertinoIcons.ellipsis,
                                size: 16,
                                color: SpotColors.textTertiary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    // Reply-to indicator
                    if (post.replyToId != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(
                            CupertinoIcons.arrow_turn_up_left,
                            size: 11,
                            color: SpotColors.textTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _shortKey(post.replyToId!),
                            style: SpotType.caption.copyWith(
                              color: SpotColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                    // Caption
                    if (post.caption?.isNotEmpty == true) ...[
                      const SizedBox(height: SpotSpacing.sm),
                      Text(post.caption!, style: SpotType.body),
                    ],
                    const SizedBox(height: SpotSpacing.sm),
                    // Media
                    _PostMedia(
                      post: post,
                      isMediaLoading: isMediaLoading,
                      useFeedEdgeSwipeMediaLayout: useFeedEdgeSwipeMediaLayout,
                      onPostUpdated: onMediaUpdated,
                    ),
                    if (visibleTags.isNotEmpty) ...[
                      const SizedBox(height: SpotSpacing.sm),
                      Wrap(
                        spacing: SpotSpacing.sm,
                        runSpacing: SpotSpacing.xs,
                        children: [
                          for (final t in visibleTags)
                            GestureDetector(
                              onTap: onTagTap == null
                                  ? null
                                  : () => onTagTap!(t),
                              behavior: HitTestBehavior.opaque,
                              child: Text(
                                '#$t',
                                style: SpotType.body.copyWith(
                                  color: SpotColors.accent,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: SpotSpacing.sm),
                    _PostLocationRow(post: post),
                    if (post.isPendingRetry) ...[
                      const SizedBox(height: SpotSpacing.xs),
                      Text(
                        post.lastPublishError?.isNotEmpty == true
                            ? 'Not posted yet. Tap refresh to resend.'
                            : 'Saved locally only. Tap refresh to resend.',
                        style: SpotType.caption.copyWith(
                          color: SpotColors.warning,
                        ),
                      ),
                    ],
                    // ── Control panel: reply · like · indicators ──
                    const SizedBox(height: SpotSpacing.xs),
                    Row(
                      children: [
                        // Reply
                        _ActionButton(
                          icon: CupertinoIcons.bubble_left,
                          count: post.replyCount,
                          onTap: onReply,
                        ),
                        const SizedBox(width: SpotSpacing.lg),
                        // Like
                        _LikeActionButton(
                          count: post.displayLikeCount,
                          liked: post.isLikedByMe,
                          onTap: onLike,
                        ),
                        const Spacer(),
                        // AI-generated indicator
                        Icon(
                          CupertinoIcons.sparkles,
                          size: 14,
                          color: post.isAiGenerated
                              ? SpotColors.warning
                              : SpotColors.textTertiary.withAlpha(60),
                        ),
                        const SizedBox(width: SpotSpacing.md),
                        // Repost / secondhand indicator
                        Icon(
                          CupertinoIcons.arrow_2_squarepath,
                          size: 14,
                          color: post.sourceType == PostSourceType.secondhand
                              ? SpotColors.accent
                              : SpotColors.textTertiary.withAlpha(60),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Post media ────────────────────────────────────────────────────────────────

class _PostMedia extends StatefulWidget {
  const _PostMedia({
    required this.post,
    required this.isMediaLoading,
    required this.useFeedEdgeSwipeMediaLayout,
    this.onPostUpdated,
  });

  final MediaPost post;
  final bool isMediaLoading;
  final bool useFeedEdgeSwipeMediaLayout;
  final ValueChanged<MediaPost>? onPostUpdated;

  // Max height for a single image — keeps tall portraits from dominating the feed.
  static const double maxImageHeight = 200;

  @override
  State<_PostMedia> createState() => _PostMediaState();
}

class _PostMediaState extends State<_PostMedia> {
  bool _hasTriedAutoLoad = false;
  bool _isMediaUnavailableNow = false;
  double _feedEdgeSwipeProgress = 0;
  late final ScrollController _mediaScrollController;

  @override
  void initState() {
    super.initState();
    _mediaScrollController = ScrollController()
      ..addListener(_syncFeedEdgeSwipe);
    _tryAutoLoad();
  }

  @override
  void dispose() {
    _mediaScrollController
      ..removeListener(_syncFeedEdgeSwipe)
      ..dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_PostMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.post.id != oldWidget.post.id) {
      _hasTriedAutoLoad = false;
      _isMediaUnavailableNow = false;
      _feedEdgeSwipeProgress = 0;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_mediaScrollController.hasClients) return;
        if (_mediaScrollController.position.pixels == 0) return;
        _mediaScrollController.jumpTo(0);
      });
      _tryAutoLoad();
      return;
    }

    final hasLocalMedia = _hasLocalMedia();
    if (hasLocalMedia) {
      _isMediaUnavailableNow = false;
      return;
    }

    if (oldWidget.isMediaLoading && !widget.isMediaLoading) {
      _isMediaUnavailableNow = true;
    }
  }

  void _tryAutoLoad() {
    if (_hasTriedAutoLoad || widget.isMediaLoading) return;
    if (_isMediaUnavailableNow) return;
    if (widget.post.isTextOnly) return;

    // Check if media is already available
    final hasLocalMedia = _hasLocalMedia();
    if (hasLocalMedia) return;

    // Auto-load if only preview is available
    _hasTriedAutoLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.onPostUpdated != null) {
        widget.onPostUpdated!(widget.post);
      }
    });
  }

  void _syncFeedEdgeSwipe() {
    if (!widget.useFeedEdgeSwipeMediaLayout) return;
    if (!_mediaScrollController.hasClients) return;

    final pixels = _mediaScrollController.position.pixels;
    final effectivePixels =
        (pixels - postThreadRowFeedMediaSwipeActivationThreshold).clamp(
          0.0,
          postThreadRowFeedMediaSwipeLeftBleed,
        );
    final progress = effectivePixels / postThreadRowFeedMediaSwipeLeftBleed;
    if ((_feedEdgeSwipeProgress - progress).abs() < 0.001) return;
    setState(() => _feedEdgeSwipeProgress = progress);
  }

  Widget _buildMultiMediaList(List<({int index, String path})> availableMedia) {
    Widget buildListView(double itemWidth) => ListView.separated(
      controller: _mediaScrollController,
      scrollDirection: Axis.horizontal,
      itemCount: availableMedia.length,
      separatorBuilder: (ctx, i) =>
          const SizedBox(width: postThreadRowMediaGap),
      itemBuilder: (ctx, i) {
        final media = availableMedia[i];
        return GestureDetector(
          onTap: () => _openDetail(context, initialIndex: media.index),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: itemWidth,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SpotRadius.sm),
              child: _isVideo(media.path)
                  ? _VideoThumb(path: media.path, compact: true)
                  : Image.file(
                      File(media.path),
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) => Container(
                        color: SpotColors.surface,
                        child: const Icon(
                          CupertinoIcons.photo,
                          color: SpotColors.overlay,
                          size: 22,
                        ),
                      ),
                    ),
            ),
          ),
        );
      },
    );

    if (!widget.useFeedEdgeSwipeMediaLayout) {
      final itemWidth = availableMedia.length == 2 ? 200.0 : 160.0;
      return KeyedSubtree(
        key: postThreadRowMediaViewportKey,
        child: SizedBox(
          key: postThreadRowMediaContentKey,
          height: _PostMedia.maxImageHeight,
          child: buildListView(itemWidth),
        ),
      );
    }

    return SizedBox(
      height: _PostMedia.maxImageHeight,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final baseWidth = constraints.maxWidth;
          final itemWidth = availableMedia.length == 2
              ? postThreadRowFeedTwoImageWidth(baseWidth)
              : 160.0;
          final extraWidth =
              postThreadRowFeedMediaSwipeLeftBleed * _feedEdgeSwipeProgress;
          final expandedWidth =
              baseWidth + postThreadRowFeedMediaSwipeLeftBleed;
          final targetWidth = baseWidth + extraWidth;
          final targetOffset = -extraWidth;

          return OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: baseWidth,
            maxWidth: expandedWidth,
            minHeight: _PostMedia.maxImageHeight,
            maxHeight: _PostMedia.maxImageHeight,
            child: Transform.translate(
              key: postThreadRowMediaViewportKey,
              offset: Offset(targetOffset, 0),
              child: SizedBox(
                key: postThreadRowMediaContentKey,
                width: targetWidth,
                height: _PostMedia.maxImageHeight,
                child: buildListView(itemWidth),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.post.isTextOnly) return const SizedBox.shrink();

    final availableMedia = <({int index, String path})>[];
    for (var i = 0; i < widget.post.mediaPaths.length; i++) {
      final path = widget.post.mediaPaths[i];
      if (File(path).existsSync()) {
        availableMedia.add((index: i, path: path));
      }
    }

    if (availableMedia.length > 1) {
      return _buildMultiMediaList(availableMedia);
    }

    final media = availableMedia.isEmpty ? null : availableMedia.first;
    if (media != null) {
      final child = _isVideo(media.path)
          ? _VideoThumb(path: media.path)
          : SizedBox(
              height: _PostMedia.maxImageHeight,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SpotRadius.md),
                child: Image.file(
                  File(media.path),
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => _mediaShell(
                    child: const Icon(
                      CupertinoIcons.photo,
                      color: SpotColors.overlay,
                      size: 26,
                    ),
                  ),
                ),
              ),
            );

      return GestureDetector(
        onTap: () => _openDetail(context, initialIndex: media.index),
        behavior: HitTestBehavior.opaque,
        child: child,
      );
    }

    final previewBytes = _decodePreviewBytes();
    if (previewBytes != null) {
      return GestureDetector(
        onTap: _canRequestMedia()
            ? () => widget.onPostUpdated?.call(widget.post)
            : null,
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: _PostMedia.maxImageHeight,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(SpotRadius.md),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.memory(
                  previewBytes,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (ctx, err, stack) => _mediaShell(
                    child: const Icon(
                      CupertinoIcons.photo,
                      color: SpotColors.overlay,
                      size: 26,
                    ),
                  ),
                ),
                Positioned(
                  left: SpotSpacing.sm,
                  bottom: SpotSpacing.sm,
                  child: _TransportStatusChip(
                    label: widget.isMediaLoading
                        ? 'Loading full image…'
                        : _isMediaUnavailableNow
                        ? 'Image unavailable now'
                        : 'Tap to load full',
                    showSpinner: widget.isMediaLoading,
                  ),
                ),
                Positioned(
                  right: SpotSpacing.sm,
                  bottom: SpotSpacing.sm,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpotSpacing.sm,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xB3000000),
                      borderRadius: BorderRadius.circular(SpotRadius.full),
                    ),
                    child: Text(
                      'Preview',
                      style: SpotType.caption.copyWith(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: _canRequestMedia()
          ? () {
              // Trigger media fetch via CDN / P2P instead of opening an empty
              // detail screen.
              widget.onPostUpdated?.call(widget.post);
            }
          : null,
      behavior: HitTestBehavior.opaque,
      child: _mediaShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isMediaLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: SpotSpacing.sm),
                child: CupertinoActivityIndicator(radius: 10),
              )
            else
              Icon(
                _isMediaUnavailableNow
                    ? CupertinoIcons.exclamationmark_triangle
                    : CupertinoIcons.cloud_download,
                color: SpotColors.overlay,
                size: 26,
              ),
            Text(
              widget.isMediaLoading
                  ? 'Loading full media…'
                  : _isMediaUnavailableNow
                  ? 'Image unavailable now'
                  : 'Tap to load media',
              style: SpotType.caption.copyWith(color: SpotColors.textTertiary),
            ),
            const SizedBox(height: SpotSpacing.xs),
            Text(
              widget.isMediaLoading
                  ? 'Downloading from CDN…'
                  : _isMediaUnavailableNow
                  ? 'Check back later'
                  : 'Downloads via CDN or P2P',
              style: SpotType.caption.copyWith(
                color: SpotColors.textTertiary.withAlpha(150),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetail(BuildContext context, {int initialIndex = 0}) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaDetailScreen(
          post: widget.post,
          initialIndex: initialIndex,
          onPostUpdated: widget.onPostUpdated,
        ),
      ),
    );
  }

  Widget _mediaShell({required Widget child}) => Container(
    height: _PostMedia.maxImageHeight,
    width: double.infinity,
    decoration: BoxDecoration(
      color: SpotColors.surface,
      borderRadius: BorderRadius.circular(SpotRadius.md),
      border: Border.all(color: SpotColors.border, width: 0.5),
    ),
    child: Center(child: child),
  );

  Uint8List? _decodePreviewBytes() {
    final previewBase64 = widget.post.previewBase64;
    if (previewBase64 == null || previewBase64.isEmpty) return null;

    final mimeType = widget.post.previewMimeType;
    if (mimeType != null && !mimeType.startsWith('image/')) return null;

    try {
      return base64Decode(previewBase64);
    } catch (_) {
      return null;
    }
  }

  bool _hasLocalMedia() =>
      widget.post.mediaPaths.any((path) => File(path).existsSync());

  bool _canRequestMedia() => !widget.isMediaLoading && !_isMediaUnavailableNow;

  static bool _isVideo(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.avi') ||
        p.endsWith('.mkv');
  }
}

class _TransportStatusChip extends StatelessWidget {
  const _TransportStatusChip({required this.label, required this.showSpinner});

  final String label;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: const Color(0xB3000000),
        borderRadius: BorderRadius.circular(SpotRadius.full),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSpinner) ...[
            const CupertinoActivityIndicator(radius: 6),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: SpotType.caption.copyWith(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Video thumbnail ───────────────────────────────────────────────────────────

class _VideoThumb extends StatelessWidget {
  const _VideoThumb({required this.path, this.compact = false});
  final String path;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? double.infinity : _PostMedia.maxImageHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: SpotColors.surface,
        borderRadius: BorderRadius.circular(SpotRadius.md),
        border: Border.all(color: SpotColors.border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SpotRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Dark background
            Container(color: const Color(0xFF111111)),
            // Play icon
            const Center(
              child: Icon(
                CupertinoIcons.play_circle_fill,
                color: Colors.white54,
                size: 44,
              ),
            ),
            // "Video" label bottom-left
            Positioned(
              bottom: SpotSpacing.sm,
              left: SpotSpacing.sm,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(SpotRadius.xs),
                ),
                child: const Text(
                  'Video',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Avatar ────────────────────────────────────────────────────────────────────

/// Circular avatar derived from the first hex digit of a Nostr public key.
class PubkeyAvatar extends StatelessWidget {
  const PubkeyAvatar({super.key, required this.pubkey});

  final String pubkey;

  static const _palette = [
    Color(0xFF6B8F6F), // sage
    Color(0xFFC8B89A), // sand
    Color(0xFF7B8FA8), // slate
    Color(0xFFA08888), // dusty rose
    Color(0xFF8FA87B), // olive
    Color(0xFF8088A0), // lavender
    Color(0xFFA89060), // caramel
    Color(0xFF709090), // teal
    Color(0xFF9B8070), // terracotta
    Color(0xFF708090), // storm
    Color(0xFFB0A080), // wheat
    Color(0xFF80A090), // seafoam
    Color(0xFF90A0B0), // periwinkle
    Color(0xFF8080A8), // iris
    Color(0xFFA0A070), // moss
    Color(0xFF9090A0), // pewter
  ];

  @override
  Widget build(BuildContext context) {
    Color bg = _palette[0];
    String initials = '??';
    if (pubkey.length >= 2) {
      final idx = (int.tryParse(pubkey[0], radix: 16) ?? 0) % _palette.length;
      bg = _palette[idx];
      initials = pubkey.substring(0, 2).toUpperCase();
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: bg.withAlpha(45),
        border: Border.all(color: bg.withAlpha(90), width: 0.5),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: bg,
            fontSize: 11,
            fontFamily: 'monospace',
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }
}

// ── Private helpers ────────────────────────────────────────────────────────────

class _PostLocationRow extends StatelessWidget {
  const _PostLocationRow({required this.post});

  final MediaPost post;

  @override
  Widget build(BuildContext context) {
    final label = visibleThreadLocationTextForPost(post);
    final IconData icon;
    final Color color;

    if (post.isVirtual) {
      icon = CupertinoIcons.gamecontroller;
      color = SpotColors.textTertiary;
    } else if (!post.hasGps) {
      icon = CupertinoIcons.location_slash;
      color = SpotColors.textTertiary;
    } else if (post.isSpotCheckIn) {
      icon = CupertinoIcons.map_pin_ellipse;
      color = SpotColors.accent;
    } else {
      icon = CupertinoIcons.location;
      color = SpotColors.success.withAlpha(160);
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Icon(icon, size: 12, color: color),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            label,
            style: SpotType.caption.copyWith(color: SpotColors.textSecondary),
          ),
        ),
      ],
    );
  }
}

// ── Post badge ────────────────────────────────────────────────────────────────

class _PostBadge extends StatelessWidget {
  const _PostBadge({
    required this.label,
    required this.color,
    required this.bg,
  });
  final String label;
  final Color color;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(SpotRadius.xs),
      ),
      child: Text(label, style: SpotType.label.copyWith(color: color)),
    );
  }
}

// ── Action button (reply / like) ──────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.icon, required this.count, this.onTap});

  final IconData icon;
  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: SpotColors.textTertiary),
            const SizedBox(width: 4),
            Text(
              '$count',
              style: SpotType.caption.copyWith(color: SpotColors.textTertiary),
            ),
          ],
        ),
      ),
    );
  }
}

class _LikeActionButton extends StatelessWidget {
  const _LikeActionButton({
    required this.count,
    required this.liked,
    this.onTap,
  });

  final int count;
  final bool liked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = liked ? SpotColors.danger : SpotColors.textTertiary;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              liked ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 4),
            Text('$count', style: SpotType.caption.copyWith(color: color)),
          ],
        ),
      ),
    );
  }
}

// ── Private helpers ────────────────────────────────────────────────────────────

GeoLocation? _geoLocationForPost(MediaPost post) {
  if (!post.hasGps) return null;
  return GeoLookup.instance.nearest(post.latitude!, post.longitude!);
}

String _shortKey(String pubkey) {
  if (pubkey.length <= 12) return pubkey;
  return '${pubkey.substring(0, 6)}…${pubkey.substring(pubkey.length - 4)}';
}

String _authorDisplayNameForPost(MediaPost post) {
  final displayName = post.authorDisplayName?.trim();
  if (displayName != null && displayName.isNotEmpty) return displayName;
  return _shortKey(post.pubkey);
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('MMM d').format(dt);
}

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/screens/media_detail_screen.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/theme/spot_theme.dart';

List<String> visibleThreadTagsForPost(MediaPost post) {
  if (post.eventTags.isEmpty) return const [];
  if (post.replyToId == null) return const [];
  if (post.eventTags.length == 1) return const [];
  return post.eventTags.sublist(1);
}

String visibleThreadLocationTextForPost(
  MediaPost post, {
  GeoLocation? geoLocation,
}) {
  if (post.isVirtual) {
    return 'Virtual';
  }

  if (!post.hasGps) {
    return 'Location hidden';
  }

  final geo = geoLocation ?? _geoLocationForPost(post);
  final coordinates = _coordinateLocationLabelForPost(post);
  final place = geo != null ? '${geo.country}/${geo.city}' : null;

  if (post.isSpotCheckIn) {
    if (place != null) return '${post.spotName} - $place ($coordinates)';
    return '${post.spotName} - $coordinates';
  }

  if (place != null) return place;
  return coordinates;
}

/// Twitter/Threads-style thread row for a single [MediaPost].
///
/// Set [isLast] to true on the final row to suppress the connector line.
class PostThreadRow extends StatelessWidget {
  const PostThreadRow({
    super.key,
    required this.post,
    required this.isLast,
    this.onAvatarTap,
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
        SpotSpacing.lg,
        SpotSpacing.sm,
        SpotSpacing.lg,
        0,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Left: avatar + thread connector line ────────────────────────
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: onAvatarTap,
                    behavior: HitTestBehavior.opaque,
                    child: PubkeyAvatar(pubkey: post.pubkey),
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
            const SizedBox(width: SpotSpacing.sm),
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
                                _shortKey(post.pubkey),
                                style: SpotType.bodySecondary,
                              ),
                              if (headerCategoryTag != null)
                                ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    maxWidth: 96,
                                  ),
                                  child: Text(
                                    '#$headerCategoryTag',
                                    style: SpotType.caption.copyWith(
                                      color: SpotColors.accent,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
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
                        if (post.sourceType == PostSourceType.secondhand) ...[
                          const SizedBox(width: SpotSpacing.sm),
                          _PostBadge(
                            label: '2nd hand',
                            color: SpotColors.textSecondary,
                            bg: SpotColors.surfaceHigh,
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
                    // Event hashtags
                    if (visibleTags.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: SpotSpacing.sm,
                        children: [
                          for (final t in visibleTags)
                            Text(
                              '#$t',
                              style: SpotType.body.copyWith(
                                color: SpotColors.accent,
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
                      onPostUpdated: onMediaUpdated,
                    ),
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

class _PostMedia extends StatelessWidget {
  const _PostMedia({
    required this.post,
    required this.isMediaLoading,
    this.onPostUpdated,
  });

  final MediaPost post;
  final bool isMediaLoading;
  final ValueChanged<MediaPost>? onPostUpdated;

  // Max height for a single image — keeps tall portraits from dominating the feed.
  static const double _maxImageHeight = 200;

  @override
  Widget build(BuildContext context) {
    if (post.isTextOnly) return const SizedBox.shrink();

    final availableMedia = <({int index, String path})>[];
    for (var i = 0; i < post.mediaPaths.length; i++) {
      final path = post.mediaPaths[i];
      if (File(path).existsSync()) {
        availableMedia.add((index: i, path: path));
      }
    }

    if (availableMedia.length > 1) {
      return SizedBox(
        height: _maxImageHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: availableMedia.length,
          separatorBuilder: (ctx, i) => const SizedBox(width: 6),
          itemBuilder: (ctx, i) {
            final media = availableMedia[i];
            final width = availableMedia.length == 2 ? 200.0 : 160.0;
            return GestureDetector(
              onTap: () => _openDetail(context, initialIndex: media.index),
              behavior: HitTestBehavior.opaque,
              child: SizedBox(
                width: width,
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
        ),
      );
    }

    final media = availableMedia.isEmpty ? null : availableMedia.first;
    if (media != null) {
      final child = _isVideo(media.path)
          ? _VideoThumb(path: media.path)
          : SizedBox(
              height: _maxImageHeight,
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
        onTap: () {
          if (!isMediaLoading) {
            onPostUpdated?.call(post);
          }
        },
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          height: _maxImageHeight,
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
                    label: isMediaLoading
                        ? 'Loading full image…'
                        : 'Tap to load full',
                    showSpinner: isMediaLoading,
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
      onTap: () {
        if (!isMediaLoading) {
          // Trigger media fetch via CDN / P2P instead of opening an empty
          // detail screen.
          onPostUpdated?.call(post);
        }
      },
      behavior: HitTestBehavior.opaque,
      child: _mediaShell(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isMediaLoading)
              const Padding(
                padding: EdgeInsets.only(bottom: SpotSpacing.sm),
                child: CupertinoActivityIndicator(radius: 10),
              )
            else
              const Icon(
                CupertinoIcons.cloud_download,
                color: SpotColors.overlay,
                size: 26,
              ),
            Text(
              isMediaLoading ? 'Loading full media…' : 'Tap to load media',
              style: SpotType.caption.copyWith(color: SpotColors.textTertiary),
            ),
            const SizedBox(height: SpotSpacing.xs),
            Text(
              isMediaLoading
                  ? 'Downloading from CDN…'
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
          post: post,
          initialIndex: initialIndex,
          onPostUpdated: onPostUpdated,
        ),
      ),
    );
  }

  Widget _mediaShell({required Widget child}) => Container(
    height: _maxImageHeight,
    width: double.infinity,
    decoration: BoxDecoration(
      color: SpotColors.surface,
      borderRadius: BorderRadius.circular(SpotRadius.md),
      border: Border.all(color: SpotColors.border, width: 0.5),
    ),
    child: Center(child: child),
  );

  Uint8List? _decodePreviewBytes() {
    final previewBase64 = post.previewBase64;
    if (previewBase64 == null || previewBase64.isEmpty) return null;

    final mimeType = post.previewMimeType;
    if (mimeType != null && !mimeType.startsWith('image/')) return null;

    try {
      return base64Decode(previewBase64);
    } catch (_) {
      return null;
    }
  }

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
      height: compact ? double.infinity : _PostMedia._maxImageHeight,
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

String _coordinateLocationLabelForPost(MediaPost post) {
  final lat = post.latitude!;
  final lon = post.longitude!;
  return '${lat.toStringAsFixed(1)}, ${lon.toStringAsFixed(1)}';
}

String _shortKey(String pubkey) {
  if (pubkey.length <= 12) return pubkey;
  return '${pubkey.substring(0, 6)}…${pubkey.substring(pubkey.length - 4)}';
}

String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inSeconds < 60) return '${diff.inSeconds}s';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  if (diff.inDays < 7) return '${diff.inDays}d';
  return DateFormat('MMM d').format(dt);
}

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/theme/spot_theme.dart';

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
    this.onDelete,
    this.onReport,
  });

  final MediaPost post;
  final bool isLast;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onReply;
  final VoidCallback? onDelete;
  final VoidCallback? onReport;

  void _showPostMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: SpotColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SpotRadius.lg)),
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
                title: const Text('Cancel',
                    style: TextStyle(color: SpotColors.textSecondary)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        SpotSpacing.lg, SpotSpacing.sm, SpotSpacing.lg, 0,
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
                        Text(
                          _shortKey(post.pubkey),
                          style: SpotType.bodySecondary,
                        ),
                        const SizedBox(width: SpotSpacing.xs),
                        Text('·', style: SpotType.caption),
                        const SizedBox(width: SpotSpacing.xs),
                        Text(
                          _relativeTime(post.capturedAt),
                          style: SpotType.caption,
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
                            style: SpotType.caption
                                .copyWith(color: SpotColors.textTertiary),
                          ),
                        ],
                      ),
                    ],
                    // Event hashtags
                    if (post.eventTags.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Wrap(
                        spacing: SpotSpacing.sm,
                        children: [
                          for (final t in post.eventTags)
                            Text(
                              '#$t',
                              style: SpotType.body
                                  .copyWith(color: SpotColors.accent),
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
                    _PostMedia(post: post),
                    const SizedBox(height: SpotSpacing.sm),
                    // GPS row
                    _GpsRow(post: post),
                    // Reply button
                    if (onReply != null) ...[
                      const SizedBox(height: SpotSpacing.xs),
                      GestureDetector(
                        onTap: onReply,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                CupertinoIcons.arrow_turn_up_left,
                                size: 13,
                                color: SpotColors.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Reply',
                                style: SpotType.caption
                                    .copyWith(color: SpotColors.textTertiary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
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
  const _PostMedia({required this.post});
  final MediaPost post;

  // Max height for a single image — keeps tall portraits from dominating the feed.
  static const double _maxImageHeight = 200;

  @override
  Widget build(BuildContext context) {
    if (post.isTextOnly) return const SizedBox.shrink();

    // Collect all locally available paths (danger-mode images show blurred)
    final availablePaths = post.mediaPaths
        .where((p) => File(p).existsSync())
        .toList();

    // Multiple files: horizontal scrollable strip
    if (availablePaths.length > 1) {
      return SizedBox(
        height: _maxImageHeight,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: availablePaths.length,
          separatorBuilder: (ctx, i) => const SizedBox(width: 6),
          itemBuilder: (ctx, i) {
            final path = availablePaths[i];
            final w = availablePaths.length == 2 ? 200.0 : 160.0;
            return SizedBox(
              width: w,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SpotRadius.sm),
                child: _isVideo(path)
                    ? _VideoThumb(path: path, compact: true)
                    : Image.file(File(path),
                        fit: BoxFit.cover,
                        errorBuilder: (ctx, err, stack) => Container(
                          color: SpotColors.surface,
                          child: const Icon(CupertinoIcons.photo,
                              color: SpotColors.overlay, size: 22),
                        )),
              ),
            );
          },
        ),
      );
    }

    // Single file
    final path = availablePaths.isEmpty ? null : availablePaths.first;
    if (path != null) {
      if (_isVideo(path)) {
        return _VideoThumb(path: path);
      }
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: _maxImageHeight),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SpotRadius.md),
          child: Image.file(
            File(path),
            width: double.infinity,
            fit: BoxFit.cover,
            errorBuilder: (ctx, err, stack) => _mediaShell(
              child: const Icon(CupertinoIcons.photo,
                  color: SpotColors.overlay, size: 26),
            ),
          ),
        ),
      );
    }

    // No local file (remote post, P2P not yet fetched)
    return _mediaShell(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.photo,
              color: SpotColors.overlay, size: 26),
          const SizedBox(height: SpotSpacing.xs),
          Text('Media not synced yet',
              style:
                  SpotType.caption.copyWith(color: SpotColors.textTertiary)),
        ],
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

  static bool _isVideo(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.avi') ||
        p.endsWith('.mkv');
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius:
                      BorderRadius.circular(SpotRadius.xs),
                ),
                child: const Text('Video',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11)),
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

// ── GPS row ───────────────────────────────────────────────────────────────────

/// Displays location as "Country/City(lat,lon)" in normal mode and
/// "Country/City" in protected (danger) mode.
class _GpsRow extends StatelessWidget {
  const _GpsRow({required this.post});
  final MediaPost post;

  @override
  Widget build(BuildContext context) {
    if (post.isVirtual) {
      return Row(
        children: [
          const Icon(CupertinoIcons.gamecontroller,
              size: 11, color: SpotColors.textTertiary),
          const SizedBox(width: 4),
          Text('Virtual', style: SpotType.caption),
        ],
      );
    }

    if (!post.hasGps) {
      return Row(
        children: [
          const Icon(CupertinoIcons.location_slash,
              size: 11, color: SpotColors.textTertiary),
          const SizedBox(width: 4),
          Text('Location hidden', style: SpotType.caption),
        ],
      );
    }

    final lat = post.latitude!;
    final lon = post.longitude!;
    final geo = GeoLookup.instance.nearest(lat, lon);

    final String label;
    if (geo != null) {
      if (post.isDangerMode) {
        // Protected mode: country/city only, no coordinates
        label = '${geo.country}/${geo.city}';
      } else {
        // Normal mode: country/city(lat,lon)
        label = '${geo.country}/${geo.city}'
            '(${lat.toStringAsFixed(3)},${lon.toStringAsFixed(3)})';
      }
    } else {
      // GeoLookup not ready yet — fall back to raw coordinates
      label = post.isDangerMode
          ? '${lat.toStringAsFixed(1)}, ${lon.toStringAsFixed(1)}'
          : '${lat.toStringAsFixed(3)}, ${lon.toStringAsFixed(3)}';
    }

    return Row(
      children: [
        Icon(
          post.isDangerMode
              ? CupertinoIcons.location
              : CupertinoIcons.location_fill,
          size: 11,
          color: post.isDangerMode
              ? SpotColors.warning.withAlpha(160)
              : SpotColors.success.withAlpha(160),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: Text(label, style: SpotType.caption, maxLines: 1,
              overflow: TextOverflow.ellipsis),
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

// ── Private helpers ────────────────────────────────────────────────────────────

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

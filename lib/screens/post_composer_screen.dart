import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:mobile/core/encryption.dart';
import 'package:mobile/features/event/event_repository.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/camera_service.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

/// Shows the [PostComposerSheet] as a modal bottom sheet.
Future<void> showPostComposer(
  BuildContext context, {
  required WalletModel wallet,
  required NostrService nostrService,
  EventRepository? eventRepo,
  MediaPost? replyToPost,
  Future<GpsLock?> Function()? gpsLoader,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: SpotColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(SpotRadius.xl)),
    ),
    builder: (_) => PostComposerSheet(
      wallet: wallet,
      nostrService: nostrService,
      eventRepo: eventRepo,
      replyToPost: replyToPost,
      gpsLoader: gpsLoader,
    ),
  );
}

/// Modal bottom-sheet composer for new posts and replies.
class PostComposerSheet extends StatefulWidget {
  const PostComposerSheet({
    super.key,
    required this.wallet,
    required this.nostrService,
    this.eventRepo,
    this.replyToPost,
    this.gpsLoader,
  });

  final WalletModel wallet;
  final NostrService nostrService;
  final EventRepository? eventRepo;
  final MediaPost? replyToPost;
  final Future<GpsLock?> Function()? gpsLoader;

  @override
  State<PostComposerSheet> createState() => _PostComposerSheetState();
}

class _PostComposerSheetState extends State<PostComposerSheet> {
  final _captionCtrl = TextEditingController();
  final _tagInputCtrl = TextEditingController();
  final _captionFocus = FocusNode();
  final _tagFocus = FocusNode();
  final _picker = ImagePicker();

  final List<XFile> _mediaFiles = [];
  final List<String> _tags = [];
  GpsLock? _gpsLock;

  bool _isDangerMode = false;
  bool _isVirtual = false;
  bool _isAiGenerated = false;
  PostSourceType _sourceType = PostSourceType.firsthand;
  bool _isPublishing = false;
  bool _showOptions = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill tag from reply parent
    if (widget.replyToPost?.eventTag != null) {
      _tags.add(widget.replyToPost!.eventTag!);
    }
    _captionFocus.addListener(() {
      if (mounted) setState(() {});
    });
    _fetchGps();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _captionFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _tagInputCtrl.dispose();
    _captionFocus.dispose();
    _tagFocus.dispose();
    super.dispose();
  }

  void _addTag(String raw) {
    final tag = raw.trim().replaceAll('#', '').toLowerCase();
    if (tag.isEmpty || _tags.contains(tag)) {
      _tagInputCtrl.clear();
      return;
    }
    setState(() {
      _tags.add(tag);
      _tagInputCtrl.clear();
    });
  }

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  Future<void> _fetchGps() async {
    final lock = await (widget.gpsLoader ?? CameraService.instance.lockGPS)();
    if (mounted) setState(() => _gpsLock = lock);
  }

  Future<void> _pickGallery() async {
    final remaining = 4 - _mediaFiles.length;
    if (remaining <= 0) {
      _showSnack('Maximum 4 media items per post');
      return;
    }
    final picked = await _picker.pickMultipleMedia(limit: remaining);
    if (picked.isEmpty || !mounted) return;
    setState(() => _mediaFiles.addAll(picked));
  }

  Future<void> _takeMediaWithCamera() async {
    final choice = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'photo'),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, 'video'),
            child: const Text('Record Video'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDestructiveAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    if (4 - _mediaFiles.length <= 0) {
      _showSnack('Maximum 4 media items per post');
      return;
    }
    XFile? result;
    if (choice == 'photo') {
      result = await _picker.pickImage(source: ImageSource.camera);
    } else {
      result = await _picker.pickVideo(source: ImageSource.camera);
    }
    if (result != null && mounted) {
      setState(() => _mediaFiles.add(result!));
    }
  }

  void _removeMedia(int index) => setState(() => _mediaFiles.removeAt(index));

  bool get _canPost =>
      _captionCtrl.text.trim().isNotEmpty || _mediaFiles.isNotEmpty;

  Future<void> _onPost() async {
    if (!_canPost || _isPublishing) return;
    final confirmed = await _showLegalCheck();
    if (!confirmed) return;
    await _publish();
  }

  Future<bool> _showLegalCheck() async {
    return await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: SpotColors.surface,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(SpotRadius.xl),
            ),
          ),
          isScrollControlled: true,
          builder: (_) => const _LegalCheckSheet(),
        ) ??
        false;
  }

  Future<void> _publish() async {
    setState(() => _isPublishing = true);
    try {
      final hashes = <String>[];
      final paths = <String>[];
      var isTextOnly = false;

      for (final xfile in _mediaFiles) {
        final bytes = await File(xfile.path).readAsBytes();
        hashes.add(EncryptionUtils.sha256BytesHex(Uint8List.fromList(bytes)));
        paths.add(xfile.path);
      }

      // Text-only post: derive a deterministic temp ID from caption + timestamp
      if (hashes.isEmpty) {
        isTextOnly = true;
        final caption = _captionCtrl.text.trim();
        hashes.add(
          EncryptionUtils.sha256Hex(
            '${widget.wallet.publicKeyHex}:$caption:${DateTime.now().millisecondsSinceEpoch}',
          ),
        );
      }

      // Commit any tag that's still in the input field
      final pendingTag = _tagInputCtrl.text.trim().replaceAll('#', '').trim();
      final effectiveTags = [
        ..._tags,
        if (pendingTag.isNotEmpty && !_tags.contains(pendingTag)) pendingTag,
      ];

      final caption = _captionCtrl.text.trim();

      final post = MediaPost(
        id: hashes.first,
        pubkey: widget.wallet.publicKeyHex,
        contentHashes: hashes,
        mediaPaths: paths,
        latitude: _isDangerMode
            ? _coarseCoord(_gpsLock?.latitude)
            : _gpsLock?.latitude,
        longitude: _isDangerMode
            ? _coarseCoord(_gpsLock?.longitude)
            : _gpsLock?.longitude,
        capturedAt: _gpsLock?.timestamp ?? DateTime.now().toUtc(),
        eventTags: effectiveTags,
        isDangerMode: _isDangerMode,
        isVirtual: _isVirtual,
        isAiGenerated: _isAiGenerated,
        isTextOnly: isTextOnly,
        sourceType: _sourceType,
        caption: caption.isEmpty ? null : caption,
        replyToId: widget.replyToPost?.nostrEventId,
        nostrEventId: hashes.first,
      );

      // Register all media files in cache before publishing
      for (var i = 0; i < hashes.length; i++) {
        if (i < paths.length) {
          await CacheManager.instance.addToCache(hashes[i], paths[i]);
        }
      }

      final signed = await widget.nostrService.publishMediaPost(
        post,
        widget.wallet,
      );

      final savedPost = post.copyWith(
        id: signed.id,
        nostrEventId: signed.id,
        contentHashes: isTextOnly ? [signed.id] : post.contentHashes,
        capturedAt: DateTime.fromMillisecondsSinceEpoch(
          signed.createdAt * 1000,
        ),
      );

      await LocalPostStore.instance.savePost(savedPost);
      widget.eventRepo?.addPost(savedPost);

      for (var i = 0; i < hashes.length; i++) {
        if (i < paths.length) {
          await P2PService.instance.seedMedia(paths[i], hashes[i]);
        }
      }

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      _showSnack('Publish failed: $e');
    } finally {
      if (mounted) setState(() => _isPublishing = false);
    }
  }

  double? _coarseCoord(double? v) {
    if (v == null) return null;
    return (v / 0.5).round() * 0.5;
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ── Tag section ──────────────────────────────────────────────────────────

  void _onTagFieldChanged(String v) {
    if (v.endsWith(' ') || v.endsWith(',')) {
      _addTag(v.replaceAll(',', ''));
    }
  }

  Widget _buildTagSection() {
    final hasCategory = _tags.isNotEmpty;
    final categoryTag = hasCategory ? _tags[0] : null;
    final extraTags = hasCategory ? _tags.sublist(1) : <String>[];
    final isReply = widget.replyToPost != null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: SpotSpacing.lg),
      decoration: BoxDecoration(
        color: SpotColors.surfaceHigh,
        borderRadius: BorderRadius.circular(SpotRadius.md),
        border: Border.all(color: SpotColors.border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Category row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpotSpacing.md,
              vertical: SpotSpacing.sm,
            ),
            child: Row(
              children: [
                Icon(
                  hasCategory ? CupertinoIcons.tag_fill : CupertinoIcons.tag,
                  size: 18,
                  color: hasCategory
                      ? SpotColors.accent
                      : SpotColors.textTertiary,
                ),
                const SizedBox(width: SpotSpacing.sm),
                Expanded(
                  child: hasCategory
                      ? Row(
                          children: [
                            _TagChip(
                              tag: categoryTag!,
                              isCategory: true,
                              canRemove: !isReply,
                              onRemove: () => _removeTag(categoryTag),
                            ),
                          ],
                        )
                      : TextField(
                          controller: _tagInputCtrl,
                          focusNode: _tagFocus,
                          style: SpotType.body.copyWith(
                            color: SpotColors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: 'Category tag (e.g. AWSSummitTokyo2026)',
                            hintStyle: SpotType.body.copyWith(
                              color: SpotColors.textTertiary,
                            ),
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: SpotSpacing.sm,
                              vertical: SpotSpacing.sm,
                            ),
                            isDense: true,
                          ),
                          textInputAction: TextInputAction.done,
                          onSubmitted: _addTag,
                          onChanged: _onTagFieldChanged,
                        ),
                ),
              ],
            ),
          ),

          // ── Extra tags row (appears once category is set) ─────────────
          if (hasCategory) ...[
            const Divider(height: 1, thickness: 0.5, color: SpotColors.border),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: SpotSpacing.md,
                vertical: SpotSpacing.sm,
              ),
              child: Wrap(
                spacing: SpotSpacing.sm,
                runSpacing: SpotSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.number,
                    size: 14,
                    color: SpotColors.textTertiary,
                  ),
                  for (int i = 0; i < extraTags.length; i++)
                    _TagChip(
                      tag: extraTags[i],
                      isCategory: false,
                      canRemove: true,
                      onRemove: () => _removeTag(extraTags[i]),
                    ),
                  IntrinsicWidth(
                    child: TextField(
                      controller: _tagInputCtrl,
                      focusNode: _tagFocus,
                      style: SpotType.bodySecondary.copyWith(
                        color: SpotColors.textSecondary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Add more tags…',
                        hintStyle: SpotType.bodySecondary.copyWith(
                          color: SpotColors.textTertiary,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: SpotSpacing.sm,
                          vertical: SpotSpacing.sm,
                        ),
                        isDense: true,
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: _addTag,
                      onChanged: _onTagFieldChanged,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final sheetHeight = mq.size.height * 0.92;
    final bottomInset = mq.viewInsets.bottom;
    return SizedBox(
      height: sheetHeight,
      child: Column(
        children: [
          const _SheetHandle(),
          const SizedBox(height: SpotSpacing.sm),

          // ── Caption + avatar (fills remaining space) ─────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.lg),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  PubkeyAvatar(pubkey: widget.wallet.publicKeyHex),
                  const SizedBox(width: SpotSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.replyToPost != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.arrow_turn_up_left,
                                  size: 11,
                                  color: SpotColors.textTertiary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Reply to ${_shortKey(widget.replyToPost!.nostrEventId)}',
                                  style: SpotType.caption.copyWith(
                                    color: SpotColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.all(SpotSpacing.sm),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(SpotRadius.sm),
                            border: Border.all(
                              color: _captionFocus.hasFocus
                                  ? SpotColors.accent.withValues(alpha: 0.45)
                                  : SpotColors.border,
                              width: 0.5,
                            ),
                          ),
                          child: TextField(
                            controller: _captionCtrl,
                            focusNode: _captionFocus,
                            minLines: 4,
                            maxLines: null,
                            style: SpotType.body,
                            decoration: InputDecoration(
                              filled: false,
                              fillColor: Colors.transparent,
                              hintText: widget.replyToPost != null
                                  ? 'Write a reply…'
                                  : 'What\'s happening?',
                              hintStyle: SpotType.body.copyWith(
                                color: SpotColors.textTertiary,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              disabledBorder: InputBorder.none,
                              errorBorder: InputBorder.none,
                              focusedErrorBorder: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Media strip ─────────────────────────────────────────────────────
          if (_mediaFiles.isNotEmpty) ...[
            const SizedBox(height: SpotSpacing.sm),
            _MediaStrip(files: _mediaFiles, onRemove: _removeMedia),
          ],

          const SizedBox(height: SpotSpacing.sm),

          // ── Tag card ────────────────────────────────────────────────────
          _buildTagSection(),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              SpotSpacing.lg + SpotSpacing.md + 14 + SpotSpacing.sm,
              3,
              SpotSpacing.lg,
              0,
            ),
            child: Text(
              'First tag is the event category · press Space or , to add more',
              style: SpotType.caption.copyWith(color: SpotColors.textTertiary),
            ),
          ),

          // ── Location row ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.lg),
            child: _LocationRow(
              gpsLock: _gpsLock,
              isVirtual: _isVirtual,
              isDangerMode: _isDangerMode,
            ),
          ),

          const SizedBox(height: SpotSpacing.sm),
          const Divider(color: SpotColors.border, height: 1, thickness: 0.5),
          const SizedBox(height: SpotSpacing.sm),

          // ── Expandable options ──────────────────────────────────────────────
          if (_showOptions) ...[
            _ComposerOptions(
              isDangerMode: _isDangerMode,
              isVirtual: _isVirtual,
              isAiGenerated: _isAiGenerated,
              sourceType: _sourceType,
              onDangerChanged: (v) => setState(() {
                _isDangerMode = v;
                if (v) _isVirtual = false;
              }),
              onVirtualChanged: (v) => setState(() {
                _isVirtual = v;
                if (v) _isDangerMode = false;
              }),
              onAiChanged: (v) => setState(() => _isAiGenerated = v),
              onSourceChanged: (v) => setState(() => _sourceType = v),
            ),
            const SizedBox(height: SpotSpacing.sm),
            const Divider(color: SpotColors.border, height: 1, thickness: 0.5),
            const SizedBox(height: SpotSpacing.sm),
          ],

          // ── Bottom toolbar ──────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.lg),
            child: Row(
              children: [
                // Gallery picker
                _ToolButton(
                  icon: CupertinoIcons.photo_on_rectangle,
                  onTap: _pickGallery,
                ),
                const SizedBox(width: SpotSpacing.sm),
                // Camera
                _ToolButton(
                  icon: CupertinoIcons.camera,
                  onTap: _takeMediaWithCamera,
                ),
                const SizedBox(width: SpotSpacing.sm),
                // More options toggle
                _ToolButton(
                  icon: CupertinoIcons.slider_horizontal_3,
                  onTap: () => setState(() => _showOptions = !_showOptions),
                  active:
                      _showOptions ||
                      _isDangerMode ||
                      _isVirtual ||
                      _isAiGenerated ||
                      _sourceType == PostSourceType.secondhand,
                ),
                const Spacer(),
                // Post button
                GestureDetector(
                  onTap: _canPost ? _onPost : null,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: SpotSpacing.lg,
                      vertical: SpotSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: _canPost
                          ? SpotColors.accent
                          : SpotColors.surfaceHigh,
                      borderRadius: BorderRadius.circular(SpotRadius.full),
                    ),
                    child: _isPublishing
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: SpotColors.onAccent,
                            ),
                          )
                        : Text(
                            'Post',
                            style: SpotType.label.copyWith(
                              color: _canPost
                                  ? SpotColors.onAccent
                                  : SpotColors.textTertiary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
          // Keyboard spacer — grows as keyboard slides up so toolbar
          // always stays visible above it.
          AnimatedContainer(
            duration: const Duration(milliseconds: 80),
            height: bottomInset > 0 ? bottomInset : SpotSpacing.md,
          ),
        ],
      ),
    );
  }
}

// ── Composer options panel ─────────────────────────────────────────────────────

class _ComposerOptions extends StatelessWidget {
  const _ComposerOptions({
    required this.isDangerMode,
    required this.isVirtual,
    required this.isAiGenerated,
    required this.sourceType,
    required this.onDangerChanged,
    required this.onVirtualChanged,
    required this.onAiChanged,
    required this.onSourceChanged,
  });

  final bool isDangerMode;
  final bool isVirtual;
  final bool isAiGenerated;
  final PostSourceType sourceType;
  final ValueChanged<bool> onDangerChanged;
  final ValueChanged<bool> onVirtualChanged;
  final ValueChanged<bool> onAiChanged;
  final ValueChanged<PostSourceType> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Post mode pills ────────────────────────────────────────────────
          Text('Post mode', style: SpotType.caption),
          const SizedBox(height: SpotSpacing.sm),
          Row(
            children: [
              _ModePill(
                icon: CupertinoIcons.location_fill,
                label: 'Real',
                active: !isDangerMode && !isVirtual,
                activeColor: SpotColors.success,
                onTap: () {
                  onDangerChanged(false);
                  onVirtualChanged(false);
                },
              ),
              const SizedBox(width: SpotSpacing.sm),
              _ModePill(
                icon: CupertinoIcons.shield_lefthalf_fill,
                label: 'Protected',
                active: isDangerMode,
                activeColor: SpotColors.danger,
                onTap: () => onDangerChanged(!isDangerMode),
              ),
              const SizedBox(width: SpotSpacing.sm),
              _ModePill(
                icon: CupertinoIcons.gamecontroller,
                label: 'Virtual',
                active: isVirtual,
                activeColor: SpotColors.accent,
                onTap: () => onVirtualChanged(!isVirtual),
              ),
            ],
          ),
          const SizedBox(height: SpotSpacing.md),

          // ── AI-generated toggle ────────────────────────────────────────────
          _OptionRow(
            icon: CupertinoIcons.sparkles,
            label: 'AI-generated content',
            subtitle: 'Content was created or assisted by AI',
            value: isAiGenerated,
            onChanged: onAiChanged,
            activeColor: SpotColors.warning,
          ),
          const SizedBox(height: SpotSpacing.sm),

          // ── Source type toggle ─────────────────────────────────────────────
          _OptionRow(
            icon: CupertinoIcons.person_2,
            label: 'Someone else\'s story',
            subtitle: 'You are sharing a secondhand account',
            value: sourceType == PostSourceType.secondhand,
            onChanged: (v) => onSourceChanged(
              v ? PostSourceType.secondhand : PostSourceType.firsthand,
            ),
            activeColor: SpotColors.accent,
          ),
        ],
      ),
    );
  }
}

// ── Mode pill ──────────────────────────────────────────────────────────────────

class _ModePill extends StatelessWidget {
  const _ModePill({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = active ? activeColor.withAlpha(30) : SpotColors.surfaceHigh;
    final fg = active ? activeColor : SpotColors.textSecondary;
    final border = active ? activeColor.withAlpha(80) : SpotColors.border;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(
          horizontal: SpotSpacing.md,
          vertical: SpotSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(SpotRadius.full),
          border: Border.all(color: border, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: fg),
            const SizedBox(width: 5),
            Text(
              label,
              style: SpotType.label.copyWith(
                color: fg,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Option row (toggle) ────────────────────────────────────────────────────────

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.activeColor,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Color activeColor;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Icon(
            icon,
            size: 16,
            color: value ? activeColor : SpotColors.textTertiary,
          ),
          const SizedBox(width: SpotSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: SpotType.bodySecondary.copyWith(
                    color: value
                        ? SpotColors.textPrimary
                        : SpotColors.textSecondary,
                  ),
                ),
                Text(subtitle, style: SpotType.caption),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: activeColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ],
      ),
    );
  }
}

// ── Media strip ────────────────────────────────────────────────────────────────

class _MediaStrip extends StatelessWidget {
  const _MediaStrip({required this.files, required this.onRemove});

  final List<XFile> files;
  final void Function(int) onRemove;

  static bool _isVideo(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') ||
        p.endsWith('.mov') ||
        p.endsWith('.avi') ||
        p.endsWith('.mkv');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: SpotSpacing.lg),
        itemCount: files.length,
        separatorBuilder: (_, _) => const SizedBox(width: SpotSpacing.sm),
        itemBuilder: (ctx, i) {
          final path = files[i].path;
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(SpotRadius.sm),
                child: _isVideo(path)
                    ? Container(
                        width: 90,
                        height: 90,
                        color: SpotColors.overlay,
                        child: const Center(
                          child: Icon(
                            CupertinoIcons.play_circle_fill,
                            color: Colors.white54,
                            size: 32,
                          ),
                        ),
                      )
                    : Image.file(
                        File(path),
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          width: 90,
                          height: 90,
                          color: SpotColors.overlay,
                          child: const Icon(
                            CupertinoIcons.photo,
                            color: SpotColors.textTertiary,
                          ),
                        ),
                      ),
              ),
              // Remove button
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => onRemove(i),
                  child: Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(SpotRadius.full),
                    ),
                    child: const Icon(
                      CupertinoIcons.xmark,
                      size: 11,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Tool button ────────────────────────────────────────────────────────────────

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(SpotSpacing.xs),
        child: Icon(
          icon,
          size: 20,
          color: active ? SpotColors.accent : SpotColors.textSecondary,
        ),
      ),
    );
  }
}

// ── Sheet handle ──────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: SpotSpacing.md),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: SpotColors.border,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

// ── Legal compliance check sheet ─────────────────────────────────────────────

class _LegalCheckSheet extends StatefulWidget {
  const _LegalCheckSheet();

  @override
  State<_LegalCheckSheet> createState() => _LegalCheckSheetState();
}

class _LegalCheckSheetState extends State<_LegalCheckSheet> {
  bool _accuracy = false;
  bool _rights = false;
  bool _noDefamation = false;
  bool _legalCompliance = false;

  bool get _allChecked =>
      _accuracy && _rights && _noDefamation && _legalCompliance;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(SpotSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _SheetHandle(),
            const SizedBox(height: SpotSpacing.lg),
            Text('Before you post', style: SpotType.subheading),
            const SizedBox(height: SpotSpacing.xs),
            Text(
              'Please confirm all of the following before sharing.',
              style: SpotType.caption,
            ),
            const SizedBox(height: SpotSpacing.xl),
            _LegalCheckbox(
              value: _accuracy,
              label:
                  'The information I\'m sharing is accurate to the best of my knowledge',
              onChanged: (v) => setState(() => _accuracy = v),
            ),
            _LegalCheckbox(
              value: _rights,
              label: 'I have the rights to share this content',
              onChanged: (v) => setState(() => _rights = v),
            ),
            _LegalCheckbox(
              value: _noDefamation,
              label: 'This content does not defame any individuals or groups',
              onChanged: (v) => setState(() => _noDefamation = v),
            ),
            _LegalCheckbox(
              value: _legalCompliance,
              label:
                  'I confirm this complies with applicable laws in my jurisdiction',
              onChanged: (v) => setState(() => _legalCompliance = v),
            ),
            const SizedBox(height: SpotSpacing.xl),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _allChecked
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(vertical: SpotSpacing.md),
                  decoration: BoxDecoration(
                    color: _allChecked
                        ? SpotColors.accent
                        : SpotColors.surfaceHigh,
                    borderRadius: BorderRadius.circular(SpotRadius.md),
                  ),
                  child: Center(
                    child: Text(
                      'Confirm & Post',
                      style: SpotType.body.copyWith(
                        color: _allChecked
                            ? SpotColors.onAccent
                            : SpotColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: SpotSpacing.sm),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () => Navigator.of(context).pop(false),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: SpotSpacing.sm,
                    ),
                    child: Text(
                      'Cancel',
                      style: SpotType.body.copyWith(
                        color: SpotColors.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegalCheckbox extends StatelessWidget {
  const _LegalCheckbox({
    required this.value,
    required this.label,
    required this.onChanged,
  });

  final bool value;
  final String label;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: SpotSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 20,
              height: 20,
              margin: const EdgeInsets.only(top: 1),
              decoration: BoxDecoration(
                color: value ? SpotColors.accent : Colors.transparent,
                border: Border.all(
                  color: value ? SpotColors.accent : SpotColors.border,
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(SpotRadius.xs),
              ),
              child: value
                  ? const Icon(
                      CupertinoIcons.checkmark,
                      size: 13,
                      color: SpotColors.onAccent,
                    )
                  : null,
            ),
            const SizedBox(width: SpotSpacing.sm),
            Expanded(child: Text(label, style: SpotType.body)),
          ],
        ),
      ),
    );
  }
}

// ── Tag chip ──────────────────────────────────────────────────────────────────

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.onRemove,
    this.isCategory = false,
    this.canRemove = true,
  });
  final String tag;
  final VoidCallback onRemove;
  final bool isCategory;
  final bool canRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.md,
        vertical: SpotSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: isCategory
            ? SpotColors.accent.withValues(alpha: 0.18)
            : SpotColors.accentSubtle,
        borderRadius: BorderRadius.circular(SpotRadius.full),
        border: Border.all(
          color: isCategory
              ? SpotColors.accent.withValues(alpha: 0.7)
              : SpotColors.accent.withAlpha(60),
          width: isCategory ? 1.0 : 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCategory) ...[
            const Icon(
              CupertinoIcons.tag_fill,
              size: 11,
              color: SpotColors.accent,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            '#$tag',
            style: SpotType.bodySecondary.copyWith(
              color: SpotColors.accent,
              fontWeight: isCategory ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          if (canRemove) ...[
            const SizedBox(width: 6),
            GestureDetector(
              onTap: onRemove,
              child: const Icon(
                CupertinoIcons.xmark_circle_fill,
                size: 14,
                color: SpotColors.accent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Location row ──────────────────────────────────────────────────────────────

class _LocationRow extends StatelessWidget {
  const _LocationRow({
    required this.gpsLock,
    required this.isVirtual,
    required this.isDangerMode,
  });

  final GpsLock? gpsLock;
  final bool isVirtual;
  final bool isDangerMode;

  @override
  Widget build(BuildContext context) {
    // Virtual mode
    if (isVirtual) {
      return Row(
        children: [
          const Icon(
            CupertinoIcons.gamecontroller,
            size: 12,
            color: SpotColors.accent,
          ),
          const SizedBox(width: 5),
          Text(
            'Virtual — location not published',
            style: SpotType.caption.copyWith(color: SpotColors.accent),
          ),
        ],
      );
    }

    // Still fetching
    if (gpsLock == null) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: SpotColors.textTertiary,
            ),
          ),
          const SizedBox(width: 5),
          Text('Locating…', style: SpotType.caption),
        ],
      );
    }

    final lat = gpsLock!.latitude;
    final lon = gpsLock!.longitude;
    final geo = GeoLookup.instance.nearest(lat, lon);

    final IconData icon;
    final Color iconColor;
    final String label;

    if (isDangerMode) {
      icon = CupertinoIcons.location;
      iconColor = SpotColors.warning.withAlpha(160);
      label = geo != null
          ? '${geo.country} / ${geo.city}  ·  Protected'
          : '${lat.toStringAsFixed(1)}, ${lon.toStringAsFixed(1)}  ·  Protected';
    } else {
      icon = CupertinoIcons.location_fill;
      iconColor = SpotColors.success.withAlpha(160);
      label = geo != null
          ? '${geo.country} / ${geo.city}'
          : '${lat.toStringAsFixed(3)}, ${lon.toStringAsFixed(3)}';
    }

    return Row(
      children: [
        Icon(icon, size: 12, color: iconColor),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            label,
            style: SpotType.caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

// ── Private helpers ────────────────────────────────────────────────────────────

String _shortKey(String pubkey) {
  if (pubkey.length <= 12) return pubkey;
  return '${pubkey.substring(0, 6)}…${pubkey.substring(pubkey.length - 4)}';
}

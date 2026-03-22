import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:mobile/core/encryption.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/camera_service.dart';
import 'package:mobile/theme/spot_theme.dart';

/// Full-screen camera UI.
/// Tap = photo · Hold = video · Shield = Danger Mode
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.wallet,
    required this.nostrService,
    this.replyToPost,
  });

  final WalletModel wallet;
  final NostrService nostrService;

  /// When set, this post is being composed as a reply to [replyToPost].
  final MediaPost? replyToPost;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  bool _isInitialized = false;
  bool _isRecording   = false;
  bool _isDangerMode  = false;
  bool _isCapturing   = false;

  GpsLock? _gpsLock;
  String _eventTag = '';
  XFile? _capturedFile;
  bool  _capturedIsVideo = false;

  final _tagController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
    _fetchGps();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      _controller!.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    _tagController.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await CameraService.instance.initialize();
      if (_cameras.isEmpty) return;
      _controller = CameraController(
        _cameras.first,
        ResolutionPreset.high,
        enableAudio: true,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await _controller!.initialize();
      if (mounted) setState(() => _isInitialized = true);
    } catch (_) {}
  }

  Future<void> _fetchGps() async {
    final lock = await CameraService.instance.lockGPS();
    if (mounted) setState(() => _gpsLock = lock);
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || _isCapturing) return;
    setState(() => _isCapturing = true);
    HapticFeedback.lightImpact();
    try {
      final gps = await CameraService.instance.lockGPS();
      if (mounted) setState(() => _gpsLock = gps);
      final xfile = await CameraService.instance.capturePhoto(_controller!);
      if (mounted) setState(() { _capturedFile = xfile; _capturedIsVideo = false; });
    } catch (e) {
      _showError('Capture failed: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _startRecording() async {
    if (_controller == null || _isRecording) return;
    HapticFeedback.mediumImpact();
    final gps = await CameraService.instance.lockGPS();
    if (mounted) setState(() => _gpsLock = gps);
    await CameraService.instance.startRecording(_controller!);
    if (mounted) setState(() => _isRecording = true);
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;
    HapticFeedback.lightImpact();
    try {
      final xfile = await CameraService.instance.stopRecording(_controller!);
      if (mounted) {
        setState(() { _capturedFile = xfile; _capturedIsVideo = true; _isRecording = false; });
      }
    } catch (e) {
      _showError('Recording failed: $e');
      if (mounted) setState(() => _isRecording = false);
    }
  }

  Future<void> _publishPost(String caption) async {
    if (_capturedFile == null) return;
    File mediaFile = File(_capturedFile!.path);
    if (_isDangerMode) {
      mediaFile = await CameraService.instance.applyFaceBlur(mediaFile);
    }
    final bytes = await mediaFile.readAsBytes();
    final contentHash = EncryptionUtils.sha256BytesHex(bytes);

    // Inherit event tag from parent post when replying
    final effectiveTag = _eventTag.isNotEmpty
        ? _eventTag
        : widget.replyToPost?.eventTag;

    final post = MediaPost(
      id:           contentHash,
      pubkey:       widget.wallet.publicKeyHex,
      contentHash:  contentHash,
      mediaPath:    mediaFile.path,
      latitude:     _isDangerMode ? null : _gpsLock?.latitude,
      longitude:    _isDangerMode ? null : _gpsLock?.longitude,
      capturedAt:   _gpsLock?.timestamp ?? DateTime.now().toUtc(),
      eventTag:     effectiveTag,
      isDangerMode: _isDangerMode,
      caption:      caption.isEmpty ? null : caption,
      replyToId:    widget.replyToPost?.nostrEventId,
      nostrEventId: contentHash,
    );

    try {
      await widget.nostrService.publishMediaPost(post, widget.wallet);
      // Register in local cache (enforces 5 GB cap) then seed to swarm
      await CacheManager.instance.addToCache(contentHash, mediaFile.path);
      await P2PService.instance.seedMedia(mediaFile.path, contentHash);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Published')),
        );
        setState(() => _capturedFile = null);
      }
    } catch (e) {
      _showError('Publish failed: $e');
    }
  }

  void _discardCapture() => setState(() => _capturedFile = null);

  Future<void> _pickFromGallery() async {
    final media = await ImagePicker().pickMedia();
    if (media == null || !mounted) return;
    final path = media.path.toLowerCase();
    final isVideo = media.mimeType?.startsWith('video') == true ||
        path.endsWith('.mp4') ||
        path.endsWith('.mov') ||
        path.endsWith('.avi') ||
        path.endsWith('.mkv');
    setState(() {
      _capturedFile = media;
      _capturedIsVideo = isVideo;
    });
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(color: SpotColors.accent, strokeWidth: 1),
          ),
        ),
      );
    }

    if (_capturedFile != null) {
      return _PreviewScreen(
        filePath:     _capturedFile!.path,
        isVideo:      _capturedIsVideo,
        isDangerMode: _isDangerMode,
        gpsLock:      _gpsLock,
        eventTag:     _eventTag.isNotEmpty ? _eventTag : widget.replyToPost?.eventTag,
        replyToPost:  widget.replyToPost,
        onConfirm:    _publishPost,
        onDiscard:    _discardCapture,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          CameraPreview(_controller!),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + SpotSpacing.sm,
            left: SpotSpacing.md,
            child: GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withAlpha(120),
                ),
                child: const Icon(
                  CupertinoIcons.chevron_back,
                  color: Colors.white70,
                  size: 18,
                ),
              ),
            ),
          ),

          // Danger mode banner
          if (_isDangerMode)
            Positioned(
              top: MediaQuery.of(context).padding.top + SpotSpacing.md,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SpotSpacing.md,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: SpotColors.danger.withAlpha(220),
                    borderRadius: BorderRadius.circular(SpotRadius.xs),
                  ),
                  child: Text(
                    'Protected mode',
                    style: SpotType.label.copyWith(
                      color: SpotColors.onDanger,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ),
            ),

          // GPS lock indicator
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: SpotSpacing.lg,
            child: _GpsIndicator(gpsLock: _gpsLock),
          ),

          // Controls
          Positioned(
            left: 0, right: 0, bottom: 0,
            child: _ControlsPanel(
              isDangerMode:     _isDangerMode,
              isRecording:      _isRecording,
              tagController:    _tagController,
              onDangerToggle:   () => setState(() => _isDangerMode = !_isDangerMode),
              onTagChanged:     (v) => _eventTag = v.replaceAll('#', '').trim(),
              onTap:            _capturePhoto,
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd:   (_) => _stopRecording(),
              onGallery:        _pickFromGallery,
            ),
          ),
        ],
      ),
    );
  }
}

// ── GPS indicator ──────────────────────────────────────────────────────────────

class _GpsIndicator extends StatelessWidget {
  const _GpsIndicator({this.gpsLock});
  final GpsLock? gpsLock;

  @override
  Widget build(BuildContext context) {
    final locked = gpsLock != null;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(140),
        borderRadius: BorderRadius.circular(SpotRadius.xs),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            locked ? CupertinoIcons.location_fill : CupertinoIcons.location,
            color: locked ? SpotColors.success : SpotColors.warning,
            size: 12,
          ),
          const SizedBox(width: SpotSpacing.xs),
          Text(
            locked
                ? '${gpsLock!.latitude.toStringAsFixed(4)}, '
                  '${gpsLock!.longitude.toStringAsFixed(4)}'
                : 'Locating…',
            style: SpotType.caption.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// ── Controls panel ─────────────────────────────────────────────────────────────

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel({
    required this.isDangerMode,
    required this.isRecording,
    required this.tagController,
    required this.onDangerToggle,
    required this.onTagChanged,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
    required this.onGallery,
  });

  final bool isDangerMode;
  final bool isRecording;
  final TextEditingController tagController;
  final VoidCallback onDangerToggle;
  final ValueChanged<String> onTagChanged;
  final VoidCallback onTap;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressEndCallback onLongPressEnd;
  final VoidCallback onGallery;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: SpotSpacing.xl,
        right: SpotSpacing.xl,
        bottom: MediaQuery.of(context).padding.bottom + SpotSpacing.xl,
        top: SpotSpacing.lg,
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black.withAlpha(200), Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Event tag input
          TextField(
            controller: tagController,
            onChanged: onTagChanged,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Event tag (optional)',
              hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
              prefixText: '# ',
              prefixStyle: const TextStyle(color: Colors.white54, fontSize: 13),
              filled: true,
              fillColor: Colors.black.withAlpha(120),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(SpotRadius.sm),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: SpotSpacing.md,
                vertical: SpotSpacing.sm,
              ),
            ),
          ),
          const SizedBox(height: SpotSpacing.lg),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Danger toggle
              GestureDetector(
                onTap: onDangerToggle,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isDangerMode
                        ? SpotColors.danger.withAlpha(40)
                        : Colors.transparent,
                    border: Border.all(
                      color: isDangerMode
                          ? SpotColors.danger
                          : Colors.white24,
                      width: 0.5,
                    ),
                  ),
                  child: Icon(
                    CupertinoIcons.shield,
                    color: isDangerMode ? SpotColors.danger : Colors.white38,
                    size: 20,
                  ),
                ),
              ),

              // Capture button
              GestureDetector(
                onTap: onTap,
                onLongPressStart: onLongPressStart,
                onLongPressEnd: onLongPressEnd,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRecording ? SpotColors.danger : Colors.white,
                    border: Border.all(
                      color: Colors.white54,
                      width: 2,
                    ),
                  ),
                  child: Icon(
                    isRecording ? CupertinoIcons.stop_fill : CupertinoIcons.circle_fill,
                    color: isRecording ? Colors.white : Colors.black,
                    size: isRecording ? 28 : 32,
                  ),
                ),
              ),

              // Placeholder — future flip-camera
              GestureDetector(
                onTap: onGallery,
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white24, width: 0.5),
                  ),
                  child: const Icon(CupertinoIcons.photo, color: Colors.white54, size: 20),
                ),
              ),
            ],
          ),

          const SizedBox(height: SpotSpacing.sm),
          Text(
            isRecording
                ? 'Release to stop'
                : 'Tap · photo   Hold · video',
            style: SpotType.caption.copyWith(color: Colors.white38),
          ),
        ],
      ),
    );
  }
}

// ── Preview / publish screen ───────────────────────────────────────────────────

class _PreviewScreen extends StatefulWidget {
  const _PreviewScreen({
    required this.filePath,
    required this.isVideo,
    required this.isDangerMode,
    this.gpsLock,
    this.eventTag,
    this.replyToPost,
    required this.onConfirm,
    required this.onDiscard,
  });

  final String filePath;
  final bool isVideo;
  final bool isDangerMode;
  final GpsLock? gpsLock;
  final String? eventTag;
  final MediaPost? replyToPost;
  final void Function(String caption) onConfirm;
  final VoidCallback onDiscard;

  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  final _captionController = TextEditingController();

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.replyToPost != null ? 'Reply' : 'Review',
          style: SpotType.subheading.copyWith(color: Colors.white),
        ),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark, size: 20),
          onPressed: widget.onDiscard,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.isVideo
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.videocam, color: Colors.white38, size: 48),
                        const SizedBox(height: SpotSpacing.sm),
                        const Text(
                          'Video captured',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : Image.file(File(widget.filePath), fit: BoxFit.contain),
          ),

          // Metadata + caption + action bar
          Container(
            padding: EdgeInsets.fromLTRB(
              SpotSpacing.lg,
              SpotSpacing.lg,
              SpotSpacing.lg,
              MediaQuery.of(context).padding.bottom + SpotSpacing.lg,
            ),
            color: SpotColors.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reply-to indicator
                if (widget.replyToPost != null) ...[
                  Row(
                    children: [
                      const Icon(
                        CupertinoIcons.arrow_turn_up_left,
                        size: 12,
                        color: SpotColors.textTertiary,
                      ),
                      const SizedBox(width: SpotSpacing.xs),
                      Text(
                        'Replying to ${_shortPubkey(widget.replyToPost!.pubkey)}',
                        style: SpotType.caption,
                      ),
                    ],
                  ),
                  const SizedBox(height: SpotSpacing.sm),
                ],

                // GPS / protection info
                _PreviewMetaRow(
                  icon: widget.isDangerMode
                      ? CupertinoIcons.shield
                      : CupertinoIcons.location_fill,
                  label: widget.isDangerMode
                      ? 'Protected — location and faces hidden'
                      : widget.gpsLock != null
                          ? '${widget.gpsLock!.latitude.toStringAsFixed(4)}, '
                            '${widget.gpsLock!.longitude.toStringAsFixed(4)}'
                          : 'No location',
                  color: widget.isDangerMode ? SpotColors.danger : SpotColors.success,
                ),
                if (widget.eventTag?.isNotEmpty == true)
                  _PreviewMetaRow(
                    icon: CupertinoIcons.tag,
                    label: '#${widget.eventTag}',
                    color: SpotColors.textSecondary,
                  ),
                const SizedBox(height: SpotSpacing.md),

                // Caption input
                TextField(
                  controller: _captionController,
                  maxLines: 3,
                  minLines: 1,
                  style: SpotType.body,
                  decoration: InputDecoration(
                    hintText: 'Add a caption… (optional)',
                    hintStyle: SpotType.body.copyWith(color: SpotColors.textTertiary),
                    filled: true,
                    fillColor: SpotColors.bg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SpotRadius.sm),
                      borderSide: const BorderSide(color: SpotColors.border, width: 0.5),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SpotRadius.sm),
                      borderSide: const BorderSide(color: SpotColors.border, width: 0.5),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SpotRadius.sm),
                      borderSide: const BorderSide(color: SpotColors.accent, width: 0.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: SpotSpacing.md,
                      vertical: SpotSpacing.sm,
                    ),
                  ),
                ),
                const SizedBox(height: SpotSpacing.lg),

                // Action buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onDiscard,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: SpotSpacing.md),
                        ),
                        child: const Text('Discard'),
                      ),
                    ),
                    const SizedBox(width: SpotSpacing.md),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () =>
                            widget.onConfirm(_captionController.text.trim()),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: SpotSpacing.md),
                        ),
                        child: const Text('Publish'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _shortPubkey(String pubkey) {
  if (pubkey.length <= 12) return pubkey;
  return '${pubkey.substring(0, 6)}…${pubkey.substring(pubkey.length - 4)}';
}

class _PreviewMetaRow extends StatelessWidget {
  const _PreviewMetaRow({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: color, size: 14),
          const SizedBox(width: SpotSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: SpotType.bodySecondary.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

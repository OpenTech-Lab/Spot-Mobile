import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:mobile/core/encryption.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/services/camera_service.dart';

/// Full-screen camera UI for recording geo-tagged media.
///
/// Features:
///   - Live camera preview
///   - Tap = photo, hold = video recording
///   - Danger Mode toggle (red shield): face blur + GPS strip
///   - GPS lock indicator shown at capture time
///   - Optional #EventTag input
///   - Post-capture preview with confirm / discard actions
///   - On confirm, publishes a Nostr event via [NostrService]
class CameraScreen extends StatefulWidget {
  const CameraScreen({
    super.key,
    required this.wallet,
    required this.nostrService,
  });

  final WalletModel wallet;
  final NostrService nostrService;

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen>
    with WidgetsBindingObserver {
  CameraController? _controller;
  List<CameraDescription> _cameras = [];

  bool _isInitialized = false;
  bool _isRecording = false;
  bool _isDangerMode = false;
  bool _isCapturing = false;

  GpsLock? _gpsLock;
  String _eventTag = '';
  XFile? _capturedFile;
  bool _capturedIsVideo = false;

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

  // ── Initialisation ────────────────────────────────────────────────────────

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
    } catch (_) {
      // Camera unavailable — show error state
    }
  }

  Future<void> _fetchGps() async {
    final lock = await CameraService.instance.lockGPS();
    if (mounted) setState(() => _gpsLock = lock);
  }

  // ── Capture actions ───────────────────────────────────────────────────────

  Future<void> _capturePhoto() async {
    if (_controller == null || _isCapturing) return;
    setState(() => _isCapturing = true);
    HapticFeedback.lightImpact();

    try {
      // Lock GPS at shutter press
      final gps = await CameraService.instance.lockGPS();
      if (mounted) setState(() => _gpsLock = gps);

      final xfile = await CameraService.instance.capturePhoto(_controller!);
      if (mounted) {
        setState(() {
          _capturedFile = xfile;
          _capturedIsVideo = false;
        });
      }
    } catch (e) {
      _showError('Photo capture failed: $e');
    } finally {
      if (mounted) setState(() => _isCapturing = false);
    }
  }

  Future<void> _startRecording() async {
    if (_controller == null || _isRecording) return;
    HapticFeedback.mediumImpact();

    // Lock GPS at recording start
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
        setState(() {
          _capturedFile = xfile;
          _capturedIsVideo = true;
          _isRecording = false;
        });
      }
    } catch (e) {
      _showError('Recording failed: $e');
      if (mounted) setState(() => _isRecording = false);
    }
  }

  // ── Publish ───────────────────────────────────────────────────────────────

  Future<void> _publishPost() async {
    if (_capturedFile == null) return;

    File mediaFile = File(_capturedFile!.path);

    // Danger Mode: apply face blur
    if (_isDangerMode) {
      mediaFile = await CameraService.instance.applyFaceBlur(mediaFile);
    }

    final bytes = await mediaFile.readAsBytes();
    final contentHash = EncryptionUtils.sha256BytesHex(bytes);

    final post = MediaPost(
      id: contentHash,
      pubkey: widget.wallet.publicKeyHex,
      contentHash: contentHash,
      mediaPath: mediaFile.path,
      latitude: _isDangerMode ? null : _gpsLock?.latitude,
      longitude: _isDangerMode ? null : _gpsLock?.longitude,
      capturedAt: _gpsLock?.timestamp ?? DateTime.now().toUtc(),
      eventTag: _eventTag.isEmpty ? null : _eventTag,
      isDangerMode: _isDangerMode,
      nostrEventId: contentHash, // will be updated after publish
    );

    try {
      await widget.nostrService.publishMediaPost(post, widget.wallet);

      // Seed media via P2P
      await P2PService.instance.seedMedia(mediaFile.path, contentHash);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Post published!'),
            backgroundColor: Color(0xFFFF4444),
          ),
        );
        setState(() => _capturedFile = null);
      }
    } catch (e) {
      _showError('Publish failed: $e');
    }
  }

  void _discardCapture() {
    setState(() => _capturedFile = null);
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF4444)),
        ),
      );
    }

    if (_capturedFile != null) {
      return _PreviewScreen(
        filePath: _capturedFile!.path,
        isVideo: _capturedIsVideo,
        isDangerMode: _isDangerMode,
        gpsLock: _gpsLock,
        eventTag: _eventTag,
        onConfirm: _publishPost,
        onDiscard: _discardCapture,
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          CameraPreview(_controller!),

          // Danger Mode badge overlay
          if (_isDangerMode)
            Positioned(
              top: MediaQuery.of(context).padding.top + 12,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4444),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield, color: Colors.white, size: 16),
                      SizedBox(width: 6),
                      Text(
                        'DANGER MODE',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // GPS indicator
          Positioned(
            top: MediaQuery.of(context).padding.top + 60,
            left: 16,
            child: _GpsIndicator(gpsLock: _gpsLock),
          ),

          // Controls overlay
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _ControlsPanel(
              isDangerMode: _isDangerMode,
              isRecording: _isRecording,
              tagController: _tagController,
              onDangerToggle: () =>
                  setState(() => _isDangerMode = !_isDangerMode),
              onTagChanged: (v) => _eventTag = v.replaceAll('#', '').trim(),
              onTap: _capturePhoto,
              onLongPressStart: (_) => _startRecording(),
              onLongPressEnd: (_) => _stopRecording(),
            ),
          ),
        ],
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade900,
      ),
    );
  }
}

// ── GPS indicator ─────────────────────────────────────────────────────────────

class _GpsIndicator extends StatelessWidget {
  const _GpsIndicator({this.gpsLock});

  final GpsLock? gpsLock;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            gpsLock != null ? Icons.gps_fixed : Icons.gps_not_fixed,
            color: gpsLock != null ? Colors.greenAccent : Colors.orange,
            size: 14,
          ),
          const SizedBox(width: 4),
          Text(
            gpsLock != null
                ? '${gpsLock!.latitude.toStringAsFixed(4)}, ${gpsLock!.longitude.toStringAsFixed(4)}'
                : 'Acquiring GPS...',
            style: const TextStyle(color: Colors.white, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Controls panel ────────────────────────────────────────────────────────────

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
  });

  final bool isDangerMode;
  final bool isRecording;
  final TextEditingController tagController;
  final VoidCallback onDangerToggle;
  final ValueChanged<String> onTagChanged;
  final VoidCallback onTap;
  final GestureLongPressStartCallback onLongPressStart;
  final GestureLongPressEndCallback onLongPressEnd;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
        top: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black, Colors.transparent],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Event tag field
          TextField(
            controller: tagController,
            onChanged: onTagChanged,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: '#EventTag (optional)',
              hintStyle: const TextStyle(color: Colors.white38),
              prefixIcon:
                  const Icon(Icons.tag, color: Colors.white38, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              filled: true,
              fillColor: Colors.black45,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Danger Mode toggle
              IconButton(
                onPressed: onDangerToggle,
                icon: Icon(
                  Icons.shield,
                  color: isDangerMode
                      ? const Color(0xFFFF4444)
                      : Colors.white38,
                  size: 32,
                ),
                tooltip: 'Danger Mode',
              ),

              // Capture button
              GestureDetector(
                onTap: onTap,
                onLongPressStart: onLongPressStart,
                onLongPressEnd: onLongPressEnd,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isRecording
                        ? const Color(0xFFFF4444)
                        : Colors.white,
                    border: Border.all(
                      color: isRecording
                          ? Colors.red.shade900
                          : Colors.white54,
                      width: 3,
                    ),
                  ),
                  child: Icon(
                    isRecording ? Icons.stop : Icons.camera_alt,
                    color: isRecording ? Colors.white : Colors.black,
                    size: 30,
                  ),
                ),
              ),

              // Placeholder for future flip-camera button
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isRecording
                ? 'RECORDING — release to stop'
                : 'Tap for photo · Hold for video',
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ── Preview screen ────────────────────────────────────────────────────────────

class _PreviewScreen extends StatelessWidget {
  const _PreviewScreen({
    required this.filePath,
    required this.isVideo,
    required this.isDangerMode,
    this.gpsLock,
    required this.eventTag,
    required this.onConfirm,
    required this.onDiscard,
  });

  final String filePath;
  final bool isVideo;
  final bool isDangerMode;
  final GpsLock? gpsLock;
  final String eventTag;
  final VoidCallback onConfirm;
  final VoidCallback onDiscard;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Review & Publish'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: onDiscard,
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: isVideo
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam,
                            color: Colors.white54, size: 64),
                        SizedBox(height: 8),
                        Text('Video captured',
                            style: TextStyle(color: Colors.white54)),
                        Text(
                            '(Video preview requires video_player package)',
                            style: TextStyle(
                                color: Colors.white30, fontSize: 11)),
                      ],
                    ),
                  )
                : Image.file(File(filePath), fit: BoxFit.contain),
          ),
          Container(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).padding.bottom + 16,
            ),
            color: const Color(0xFF1A1A1A),
            child: Column(
              children: [
                // Metadata summary
                _MetaRow(
                  icon: isDangerMode ? Icons.shield : Icons.gps_fixed,
                  label: isDangerMode
                      ? 'DANGER MODE — GPS stripped, faces blurred'
                      : gpsLock != null
                          ? '${gpsLock!.latitude.toStringAsFixed(4)}, ${gpsLock!.longitude.toStringAsFixed(4)}'
                          : 'No GPS',
                  color: isDangerMode ? const Color(0xFFFF4444) : Colors.greenAccent,
                ),
                if (eventTag.isNotEmpty)
                  _MetaRow(
                    icon: Icons.tag,
                    label: '#$eventTag',
                    color: Colors.white70,
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDiscard,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white54,
                          side: const BorderSide(color: Colors.white24),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Discard'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: onConfirm,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFFF4444),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Publish',
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16)),
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

class _MetaRow extends StatelessWidget {
  const _MetaRow(
      {required this.icon, required this.label, required this.color});

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

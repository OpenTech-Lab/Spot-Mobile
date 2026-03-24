import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import 'package:mobile/features/p2p/p2p_service.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:mobile/services/media_resolver.dart';
import 'package:mobile/services/media_sync_service.dart';
import 'package:mobile/theme/spot_theme.dart';

class MediaDetailScreen extends StatefulWidget {
  const MediaDetailScreen({
    super.key,
    required this.post,
    this.initialIndex = 0,
    this.onPostUpdated,
    this.mediaFetcher,
    this.shouldStartSwarm = true,
  });

  final MediaPost post;
  final int initialIndex;
  final ValueChanged<MediaPost>? onPostUpdated;
  final MediaFetcher? mediaFetcher;
  final bool shouldStartSwarm;

  @override
  State<MediaDetailScreen> createState() => _MediaDetailScreenState();
}

class _MediaDetailScreenState extends State<MediaDetailScreen> {
  late final PageController _pageController;
  late MediaPost _post;
  late int _currentIndex;

  bool _isHydrating = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _currentIndex = widget.initialIndex.clamp(0, _pageCount - 1).toInt();
    _pageController = PageController(initialPage: _currentIndex);

    if (_needsHydration(_post)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_hydrateCurrentPost());
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  int get _pageCount {
    if (_post.contentHashes.isNotEmpty) return _post.contentHashes.length;
    if (_post.mediaPaths.isNotEmpty) return _post.mediaPaths.length;
    return 1;
  }

  Future<void> _hydrateCurrentPost() async {
    if (_isHydrating || !_needsHydration(_post)) return;

    setState(() {
      _isHydrating = true;
      _statusMessage = null;
    });

    try {
      if (widget.shouldStartSwarm) {
        await P2PService.instance.startSwarm();
      }

      final sync = MediaSyncService(
        fetchMedia: widget.mediaFetcher ?? MediaResolver.instance.resolve,
      );
      final hydrated = await sync.hydratePost(_post);
      final changed = _mediaPathsChanged(_post, hydrated);

      if (!mounted) return;

      if (changed) {
        setState(() {
          _post = hydrated;
          _statusMessage = null;
        });
        try {
          await LocalPostStore.instance.savePost(hydrated);
        } catch (_) {
          // Persisting media upgrades should not block the viewer.
        }
        widget.onPostUpdated?.call(hydrated);
      } else if (!_hasAnyLocalMedia(hydrated)) {
        setState(() {
          _statusMessage =
              'Full media is still unavailable. Preview only for now.';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not load the full media right now.';
      });
    } finally {
      if (mounted) {
        setState(() => _isHydrating = false);
      }
    }
  }

  bool _needsHydration(MediaPost post) {
    if (post.isTextOnly || post.contentHashes.isEmpty) return false;
    for (var i = 0; i < post.contentHashes.length; i++) {
      if (_localPathForIndex(post, i) == null) return true;
    }
    return false;
  }

  bool _hasAnyLocalMedia(MediaPost post) {
    for (var i = 0; i < post.contentHashes.length; i++) {
      if (_localPathForIndex(post, i) != null) return true;
    }
    return false;
  }

  bool _mediaPathsChanged(MediaPost before, MediaPost after) {
    if (before.mediaPaths.length != after.mediaPaths.length) return true;
    for (var i = 0; i < before.mediaPaths.length; i++) {
      if (before.mediaPaths[i] != after.mediaPaths[i]) return true;
    }
    return false;
  }

  String? _localPathForIndex(MediaPost post, int index) {
    if (index >= post.mediaPaths.length) return null;
    final path = post.mediaPaths[index];
    if (path.isEmpty) return null;
    final file = File(path);
    return file.existsSync() ? path : null;
  }

  Uint8List? _previewBytesForIndex(int index) {
    if (index != 0) return null;
    final previewBase64 = _post.previewBase64;
    if (previewBase64 == null || previewBase64.isEmpty) return null;
    final mimeType = _post.previewMimeType;
    if (mimeType != null && !mimeType.startsWith('image/')) return null;
    try {
      return base64Decode(previewBase64);
    } catch (_) {
      return null;
    }
  }

  bool _isVideoAtIndex(int index) {
    final path = _localPathForIndex(_post, index);
    if (path != null) return _isVideoPath(path);

    if (index == 0) {
      final mimeType = _post.previewMimeType;
      if (mimeType != null && mimeType.startsWith('video/')) return true;
    }
    return false;
  }

  String _viewerTitle() {
    final label = _isVideoAtIndex(_currentIndex) ? 'Video' : 'Image';
    if (_pageCount <= 1) return label;
    return '$label ${_currentIndex + 1}/$_pageCount';
  }

  String _loadingLabel() => _isVideoAtIndex(_currentIndex)
      ? 'Loading full video…'
      : 'Loading full image…';

  @override
  Widget build(BuildContext context) {
    final canRetry = !_isHydrating && _needsHydration(_post);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          _viewerTitle(),
          style: SpotType.subheading.copyWith(color: Colors.white),
        ),
        actions: [
          if (canRetry)
            TextButton(
              onPressed: _hydrateCurrentPost,
              child: Text(
                'Retry',
                style: SpotType.bodySecondary.copyWith(color: Colors.white70),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: _pageCount,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) => _buildPage(index),
          ),
          if (_pageCount > 1)
            Positioned(
              bottom: 18,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x66000000),
                      borderRadius: BorderRadius.circular(SpotRadius.full),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpotSpacing.md,
                        vertical: SpotSpacing.xs,
                      ),
                      child: Text(
                        '${_currentIndex + 1} / $_pageCount',
                        style: SpotType.caption.copyWith(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          if (_isHydrating && _localPathForIndex(_post, _currentIndex) == null)
            Positioned.fill(
              child: _LoadingOverlay(label: _loadingLabel(), onTapRetry: null),
            )
          else if (_statusMessage != null)
            Positioned(
              left: SpotSpacing.lg,
              right: SpotSpacing.lg,
              bottom: 54,
              child: _StatusBanner(
                message: _statusMessage!,
                onRetry: canRetry ? _hydrateCurrentPost : null,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPage(int index) {
    final localPath = _localPathForIndex(_post, index);
    if (localPath != null) {
      if (_isVideoPath(localPath)) {
        return Center(child: _VideoDetailPlayer(path: localPath));
      }
      return _ImageStage.file(path: localPath);
    }

    final previewBytes = _previewBytesForIndex(index);
    if (previewBytes != null) {
      return _ImageStage.memory(bytes: previewBytes);
    }

    return _UnavailableMediaStage(
      isVideo: _isVideoAtIndex(index),
      message: _isHydrating ? _loadingLabel() : 'Tap retry to load full media',
    );
  }
}

class _ImageStage extends StatelessWidget {
  const _ImageStage.file({required this.path}) : bytes = null, _isFile = true;

  const _ImageStage.memory({required this.bytes})
    : path = null,
      _isFile = false;

  final String? path;
  final Uint8List? bytes;
  final bool _isFile;

  @override
  Widget build(BuildContext context) {
    final image = _isFile
        ? Image.file(
            File(path!),
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const _UnavailableMediaStage(
              isVideo: false,
              message: 'Could not render this image',
            ),
          )
        : Image.memory(
            bytes!,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const _UnavailableMediaStage(
              isVideo: false,
              message: 'Could not render this preview',
            ),
          );

    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: InteractiveViewer(minScale: 1, maxScale: 4, child: image),
      ),
    );
  }
}

class _VideoDetailPlayer extends StatefulWidget {
  const _VideoDetailPlayer({required this.path});

  final String path;

  @override
  State<_VideoDetailPlayer> createState() => _VideoDetailPlayerState();
}

class _VideoDetailPlayerState extends State<_VideoDetailPlayer> {
  late final VideoPlayerController _controller;
  late final Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.path));
    _initialization = _controller.initialize().then((_) async {
      await _controller.setLooping(true);
      await _controller.play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_controller.value.isInitialized) return;
    if (_controller.value.isPlaying) {
      _controller.pause();
    } else {
      _controller.play();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initialization,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done ||
            !_controller.value.isInitialized) {
          return const _UnavailableMediaStage(
            isVideo: true,
            message: 'Preparing video…',
            showSpinner: true,
          );
        }

        final aspectRatio = _controller.value.aspectRatio > 0
            ? _controller.value.aspectRatio
            : 16 / 9;

        return GestureDetector(
          onTap: _togglePlayback,
          behavior: HitTestBehavior.opaque,
          child: ColoredBox(
            color: Colors.black,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Center(
                  child: AspectRatio(
                    aspectRatio: aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                ),
                AnimatedOpacity(
                  opacity: _controller.value.isPlaying ? 0 : 1,
                  duration: const Duration(milliseconds: 180),
                  child: const Icon(
                    CupertinoIcons.play_circle_fill,
                    size: 76,
                    color: Colors.white70,
                  ),
                ),
                Positioned(
                  bottom: SpotSpacing.xl,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0x66000000),
                      borderRadius: BorderRadius.circular(SpotRadius.full),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: SpotSpacing.md,
                        vertical: SpotSpacing.xs,
                      ),
                      child: Text(
                        _controller.value.isPlaying
                            ? 'Tap to pause'
                            : 'Tap to play',
                        style: SpotType.caption.copyWith(color: Colors.white70),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  const _LoadingOverlay({required this.label, this.onTapRetry});

  final String label;
  final VoidCallback? onTapRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0x55000000),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xCC111111),
            borderRadius: BorderRadius.circular(SpotRadius.lg),
            border: Border.all(color: Colors.white12, width: 0.5),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: SpotSpacing.xl,
              vertical: SpotSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: SpotSpacing.md),
                Text(
                  label,
                  style: SpotType.body.copyWith(color: Colors.white),
                  textAlign: TextAlign.center,
                ),
                if (onTapRetry != null) ...[
                  const SizedBox(height: SpotSpacing.md),
                  TextButton(onPressed: onTapRetry, child: const Text('Retry')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC111111),
        borderRadius: BorderRadius.circular(SpotRadius.lg),
        border: Border.all(color: Colors.white12, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(SpotSpacing.md),
        child: Row(
          children: [
            const Icon(
              CupertinoIcons.info_circle,
              size: 18,
              color: Colors.white70,
            ),
            const SizedBox(width: SpotSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: SpotType.bodySecondary.copyWith(color: Colors.white70),
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(width: SpotSpacing.sm),
              TextButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ],
        ),
      ),
    );
  }
}

class _UnavailableMediaStage extends StatelessWidget {
  const _UnavailableMediaStage({
    required this.isVideo,
    required this.message,
    this.showSpinner = false,
  });

  final bool isVideo;
  final String message;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSpinner)
              const Padding(
                padding: EdgeInsets.only(bottom: SpotSpacing.md),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white70,
                  ),
                ),
              )
            else
              Icon(
                isVideo ? CupertinoIcons.play_rectangle : CupertinoIcons.photo,
                size: 42,
                color: Colors.white38,
              ),
            if (!showSpinner) const SizedBox(height: SpotSpacing.md),
            Text(
              message,
              style: SpotType.bodySecondary.copyWith(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

bool _isVideoPath(String path) {
  final lower = path.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.avi') ||
      lower.endsWith('.mkv');
}

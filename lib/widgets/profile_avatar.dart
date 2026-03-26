import 'dart:io';

import 'package:flutter/material.dart';

import 'package:mobile/services/cache_manager.dart';
import 'package:mobile/services/cdn_media_service.dart';
import 'package:mobile/theme/spot_theme.dart';

class ProfileAvatar extends StatefulWidget {
  const ProfileAvatar({
    super.key,
    required this.pubkey,
    this.avatarContentHash,
    this.size = 72,
  });

  final String pubkey;
  final String? avatarContentHash;
  final double size;

  @override
  State<ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<ProfileAvatar> {
  Future<File?>? _avatarFuture;

  @override
  void initState() {
    super.initState();
    _avatarFuture = _resolveAvatar();
  }

  @override
  void didUpdateWidget(ProfileAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.avatarContentHash != widget.avatarContentHash ||
        oldWidget.pubkey != widget.pubkey ||
        oldWidget.size != widget.size) {
      _avatarFuture = _resolveAvatar();
    }
  }

  Future<File?> _resolveAvatar() async {
    final contentHash = widget.avatarContentHash?.trim();
    if (contentHash == null || contentHash.isEmpty) return null;

    final cached = CacheManager.instance.getCached(contentHash);
    if (cached != null && cached.existsSync()) {
      return cached;
    }

    return CdnMediaService.instance.fetchFromCdn(
      contentHash,
      ignorePreference: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final contentHash = widget.avatarContentHash?.trim();
    if (contentHash == null || contentHash.isEmpty) {
      return _GeneratedProfileAvatar(pubkey: widget.pubkey, size: widget.size);
    }

    return FutureBuilder<File?>(
      future: _avatarFuture,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file != null && file.existsSync()) {
          return Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: SpotColors.surface,
              border: Border.all(
                color: SpotColors.border.withAlpha(140),
                width: widget.size >= 60 ? 1 : 0.5,
              ),
              image: DecorationImage(image: FileImage(file), fit: BoxFit.cover),
            ),
          );
        }
        return _GeneratedProfileAvatar(
          pubkey: widget.pubkey,
          size: widget.size,
        );
      },
    );
  }
}

class _GeneratedProfileAvatar extends StatelessWidget {
  const _GeneratedProfileAvatar({required this.pubkey, required this.size});

  final String pubkey;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hex = pubkey.length >= 6 ? pubkey.substring(0, 6) : '888480';
    final value = int.tryParse(hex, radix: 16) ?? 0x888480;
    final accent = Color.fromARGB(
      255,
      ((value >> 16) & 0xFF).clamp(80, 200),
      ((value >> 8) & 0xFF).clamp(80, 180),
      (value & 0xFF).clamp(60, 160),
    );
    final initials = pubkey.length >= 2
        ? pubkey.substring(0, 2).toUpperCase()
        : '??';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SpotColors.surface,
        border: Border.all(
          color: accent.withAlpha(120),
          width: size >= 60 ? 1 : 0.5,
        ),
      ),
      child: Center(
        child: Text(
          initials,
          style: TextStyle(
            color: accent,
            fontSize: size * 0.36,
            fontWeight: FontWeight.w300,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

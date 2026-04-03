import 'dart:async';

import 'package:flutter/material.dart';

import 'package:mobile/features/metadata/metadata_service.dart';
import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/services/follow_service.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/profile_avatar.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<String> _blocked = [];
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = FollowService.instance.changes.listen((_) {
      if (mounted) _reload();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _reload() {
    setState(() {
      _blocked = FollowService.instance.blocked;
    });
  }

  Future<void> _confirmUnblock(BuildContext context, String pubkey) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: Text(
              l10n.blockedUsersUnblockConfirmTitle,
              style: SpotType.subheading,
            ),
            content: Text(
              l10n.blockedUsersUnblockConfirmBody,
              style: SpotType.bodySecondary,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(l10n.cancelAction),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(
                  l10n.blockedUsersUnblockButton,
                  style: TextStyle(color: SpotColors.accent),
                ),
              ),
            ],
          ),
    );
    if (confirmed == true) {
      await FollowService.instance.unblock(pubkey);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: SpotColors.bg,
      appBar: AppBar(
        backgroundColor: SpotColors.bg,
        title: Text(l10n.blockedUsersTitle, style: SpotType.subheading),
      ),
      body: SafeArea(
        child:
            _blocked.isEmpty
                ? Center(
                  child: Text(
                    l10n.blockedUsersEmpty,
                    style: SpotType.bodySecondary,
                    textAlign: TextAlign.center,
                  ),
                )
                : ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    vertical: SpotSpacing.md,
                  ),
                  itemCount: _blocked.length,
                  separatorBuilder: (context, i) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final pubkey = _blocked[index];
                    return _BlockedUserTile(
                      pubkey: pubkey,
                      onUnblock: () => _confirmUnblock(context, pubkey),
                    );
                  },
                ),
      ),
    );
  }
}

class _BlockedUserTile extends StatefulWidget {
  const _BlockedUserTile({required this.pubkey, required this.onUnblock});

  final String pubkey;
  final VoidCallback onUnblock;

  @override
  State<_BlockedUserTile> createState() => _BlockedUserTileState();
}

class _BlockedUserTileState extends State<_BlockedUserTile> {
  ProfileModel? _profile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final profile = await MetadataService.instance.fetchProfileByPubkey(
      widget.pubkey,
    );
    if (mounted) setState(() => _profile = profile);
  }

  String get _displayName {
    final name = _profile?.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final pk = widget.pubkey;
    return pk.length > 12 ? '${pk.substring(0, 6)}…${pk.substring(pk.length - 6)}' : pk;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: SpotSpacing.xxl,
        vertical: SpotSpacing.sm,
      ),
      leading: ProfileAvatar(
        pubkey: widget.pubkey,
        avatarContentHash: _profile?.avatarContentHash,
        size: 40,
      ),
      title: Text(_displayName, style: SpotType.body),
      trailing: OutlinedButton(
        onPressed: widget.onUnblock,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(
            horizontal: SpotSpacing.lg,
            vertical: SpotSpacing.xs,
          ),
          side: BorderSide(color: SpotColors.accent),
          foregroundColor: SpotColors.accent,
          textStyle: SpotType.bodySecondary,
        ),
        child: Text(l10n.blockedUsersUnblockButton),
      ),
    );
  }
}

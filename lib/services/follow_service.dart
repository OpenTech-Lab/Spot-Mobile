import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// On-device follow/mute/block list (JSON file, never leaves the device).
class FollowService {
  FollowService._();

  static final FollowService instance = FollowService._();

  static const _fileName = 'follow_data.json';

  Set<String> _following = {};
  Set<String> _muted = {};
  Set<String> _blocked = {};
  bool _loaded = false;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_loaded) return;
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _following = Set<String>.from(data['following'] as List? ?? []);
        _muted     = Set<String>.from(data['muted']     as List? ?? []);
        _blocked   = Set<String>.from(data['blocked']   as List? ?? []);
      }
    } catch (_) {}
    _loaded = true;
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  bool isFollowing(String pubkey) => _following.contains(pubkey);
  bool isMuted(String pubkey)     => _muted.contains(pubkey);
  bool isBlocked(String pubkey)   => _blocked.contains(pubkey);

  List<String> get following => _following.toList();

  // ── Follow ────────────────────────────────────────────────────────────────

  Future<void> follow(String pubkey) async {
    _following.add(pubkey);
    await _save();
  }

  Future<void> unfollow(String pubkey) async {
    _following.remove(pubkey);
    await _save();
  }

  // ── Mute ──────────────────────────────────────────────────────────────────

  Future<void> mute(String pubkey) async {
    _muted.add(pubkey);
    _following.remove(pubkey); // implicit unfollow
    await _save();
  }

  Future<void> unmute(String pubkey) async {
    _muted.remove(pubkey);
    await _save();
  }

  // ── Block ─────────────────────────────────────────────────────────────────

  Future<void> block(String pubkey) async {
    _blocked.add(pubkey);
    _following.remove(pubkey); // implicit unfollow
    _muted.add(pubkey);        // implicit mute
    await _save();
  }

  Future<void> unblock(String pubkey) async {
    _blocked.remove(pubkey);
    _muted.remove(pubkey);
    await _save();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(jsonEncode({
        'following': _following.toList(),
        'muted':     _muted.toList(),
        'blocked':   _blocked.toList(),
      }));
    } catch (_) {}
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}

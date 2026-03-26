import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:mobile/core/tag_normalizer.dart';
import 'package:path_provider/path_provider.dart';

/// On-device follow/mute/block list (JSON file, never leaves the device).
class FollowService {
  FollowService._();

  static final FollowService instance = FollowService._();

  static const _fileName = 'follow_data.json';

  Set<String> _following = {};
  Set<String> _muted = {};
  Set<String> _blocked = {};
  Set<String> _followedTags = {};
  bool _loaded = false;
  final _changes = StreamController<void>.broadcast();

  Stream<void> get changes => _changes.stream;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> init() async {
    if (_loaded) return;
    try {
      final file = await _file();
      if (await file.exists()) {
        final raw = await file.readAsString();
        final data = jsonDecode(raw) as Map<String, dynamic>;
        _following = Set<String>.from(data['following'] as List? ?? []);
        _muted = Set<String>.from(data['muted'] as List? ?? []);
        _blocked = Set<String>.from(data['blocked'] as List? ?? []);
        _followedTags = (data['followedTags'] as List? ?? const [])
            .map((tag) => normalizeTag(tag.toString()))
            .where((tag) => tag.isNotEmpty)
            .toSet();
      }
    } catch (_) {}
    _loaded = true;
  }

  // ── Queries ───────────────────────────────────────────────────────────────

  bool isFollowing(String pubkey) => _following.contains(pubkey);
  bool isMuted(String pubkey) => _muted.contains(pubkey);
  bool isBlocked(String pubkey) => _blocked.contains(pubkey);
  bool isFollowingTag(String tag) => _followedTags.contains(normalizeTag(tag));

  List<String> get following => _following.toList();
  List<String> get followedTags => _followedTags.toList()..sort();

  // ── Follow tag ────────────────────────────────────────────────────────────

  Future<void> followTag(String tag) async {
    final normalized = normalizeTag(tag);
    if (normalized.isEmpty) return;
    _followedTags.add(normalized);
    await _save();
    _emitChange();
  }

  Future<void> unfollowTag(String tag) async {
    final normalized = normalizeTag(tag);
    if (normalized.isEmpty) return;
    _followedTags.remove(normalized);
    await _save();
    _emitChange();
  }

  // ── Follow ────────────────────────────────────────────────────────────────

  Future<void> follow(String pubkey) async {
    _following.add(pubkey);
    await _save();
    _emitChange();
  }

  Future<void> unfollow(String pubkey) async {
    _following.remove(pubkey);
    await _save();
    _emitChange();
  }

  // ── Mute ──────────────────────────────────────────────────────────────────

  Future<void> mute(String pubkey) async {
    _muted.add(pubkey);
    _following.remove(pubkey); // implicit unfollow
    await _save();
    _emitChange();
  }

  Future<void> unmute(String pubkey) async {
    _muted.remove(pubkey);
    await _save();
    _emitChange();
  }

  // ── Block ─────────────────────────────────────────────────────────────────

  Future<void> block(String pubkey) async {
    _blocked.add(pubkey);
    _following.remove(pubkey); // implicit unfollow
    _muted.add(pubkey); // implicit mute
    await _save();
    _emitChange();
  }

  Future<void> unblock(String pubkey) async {
    _blocked.remove(pubkey);
    _muted.remove(pubkey);
    await _save();
    _emitChange();
  }

  Future<void> clearAll() async {
    _following = {};
    _muted = {};
    _blocked = {};
    _followedTags = {};
    _loaded = true;
    try {
      final file = await _file();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
    _emitChange();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _save() async {
    try {
      final file = await _file();
      await file.writeAsString(
        jsonEncode({
          'following': _following.toList(),
          'muted': _muted.toList(),
          'blocked': _blocked.toList(),
          'followedTags': _followedTags.toList(),
        }),
      );
    } catch (_) {}
  }

  Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }

  void _emitChange() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }
}

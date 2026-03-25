import 'dart:convert';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/asset_transport_policy.dart';

void main() {
  final draft = MediaPost(
    id: 'draftid',
    pubkey: 'pubkey',
    contentHashes: ['imgsha'],
    mediaPaths: ['/tmp/path.jpg'],
    latitude: 35.6,
    longitude: 139.7,
    capturedAt: DateTime.now(),
    eventTags: ['test'],
    isDangerMode: false,
    isVirtual: false,
    isAiGenerated: false,
    isTextOnly: false,
    sourceType: PostSourceType.firsthand,
    caption: 'Hello',
    nostrEventId: 'draftid',
  );
  
  final published = draft.copyWith(
    id: 'signedid',
    nostrEventId: 'signedid',
    contentHashes: draft.isTextOnly ? ['signedid'] : draft.contentHashes,
    capturedAt: DateTime.fromMillisecondsSinceEpoch(1600000000 * 1000),
    deliveryState: PostDeliveryState.sent,
    lastPublishError: null,
  );
  
  try {
    final raw = jsonEncode([published.toJson()]);
    print('Encoded: $raw');
    final decoded = jsonDecode(raw) as List;
    for (final row in decoded.whereType<Map<String, dynamic>>()) {
      final p = MediaPost.fromJson(row);
      print('Decoded ID: ${p.id}, has media: ${p.contentHashes}');
    }
  } catch(e, st) {
    print('ERR: $e\n$st');
  }
}

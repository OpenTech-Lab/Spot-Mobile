import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/asset_transport_policy.dart';

void main() {
  final post = MediaPost(
    id: 'test',
    pubkey: 'test',
    contentHashes: ['hash'],
    mediaPaths: ['path'],
    capturedAt: DateTime.now(),
    eventTags: [],
    nostrEventId: 'test',
  );
  try {
    final json = post.toJson();
    print('toJson OK');
    final restored = MediaPost.fromJson(json);
    print('fromJson OK');
  } catch (e, st) {
    print('Error: $e\n$st');
  }
}

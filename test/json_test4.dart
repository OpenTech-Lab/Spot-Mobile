import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/features/nostr/nostr_service.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/core/encryption.dart';
import 'package:mobile/services/local_post_store.dart';
import 'dart:io';

void main() async {
  try {
    final now = DateTime.now();
    final dLocal = MediaPost(
      id: 'dummy_hash_id',
      pubkey: 'pubkey123',
      contentHashes: ['dummy_hash_id'],
      mediaPaths: ['/tmp/test.jpg'],
      capturedAt: now,
      eventTags: ['test'],
      isDangerMode: false,
      isVirtual: false,
      isAiGenerated: false,
      isTextOnly: false,
      sourceType: PostSourceType.firsthand,
      caption: 'Hello',
      nostrEventId: 'dummy_hash_id',
    );

    // Simulate PostPublishService.publishDraft
    final published = dLocal.copyWith(
      id: 'actual_nostr_id',
      nostrEventId: 'actual_nostr_id',
      contentHashes: ['dummy_hash_id'], // stays exactly same!
      capturedAt: now,
      deliveryState: PostDeliveryState.sent,
    );

    Directory tmp = Directory.systemTemp.createTempSync('spottest4');
    LocalPostStore.instance.debugSetStorageDirectory(tmp);

    await LocalPostStore.instance.savePost(published);
    final loaded = await LocalPostStore.instance.loadPosts();
    print("Saved post then loaded length: ${loaded.length}");
    if (loaded.isEmpty) {
      print("POST DISAPPEARED DURING LOAD!");
    } else {
      print("Post persisted OK.");
    }
  } catch (e, st) {
    print('Failed: $e\n$st');
  }
}

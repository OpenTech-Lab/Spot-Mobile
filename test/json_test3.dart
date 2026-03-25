import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/asset_transport_policy.dart';
import 'package:mobile/services/local_post_store.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
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
  
  try {
    final tmpDir = Directory.systemTemp.createTempSync('spot_test');
    LocalPostStore.instance.debugSetStorageDirectory(tmpDir);
    await LocalPostStore.instance.savePost(draft);
    print('savePost completed.');
    final loaded = await LocalPostStore.instance.loadPosts();
    print('Loaded length: ${loaded.length}');
    if (loaded.isNotEmpty) {
      print('Loaded ID: ${loaded.first.id}');
    }
  } catch(e, st) {
    print('ERR: $e\n$st');
  }
}

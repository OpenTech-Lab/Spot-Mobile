import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/profile_model.dart';

void main() {
  test('ProfileModel.fromRow reads editable profile fields', () {
    final profile = ProfileModel.fromRow({
      'id': 'user-1',
      'display_name': 'Citizen Tokyo',
      'legacy_pubkey': 'pubkey-1',
      'legacy_npub': 'npub1test',
      'device_id': 'device-1',
      'avatar_seed': 'seed-1',
      'avatar_content_hash': 'hash-1',
    });

    expect(profile.id, 'user-1');
    expect(profile.displayName, 'Citizen Tokyo');
    expect(profile.legacyPubkey, 'pubkey-1');
    expect(profile.avatarContentHash, 'hash-1');
  });
}

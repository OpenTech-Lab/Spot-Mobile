import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/profile_model.dart';

List<MediaPost> filterPostsByBlockedAuthors(
  Iterable<MediaPost> posts, {
  required Set<String> blockedPubkeys,
}) {
  if (blockedPubkeys.isEmpty) {
    return posts.toList(growable: false);
  }

  return posts
      .where((post) => !blockedPubkeys.contains(post.pubkey))
      .toList(growable: false);
}

List<ProfileModel> filterProfilesByBlockedPubkeys(
  Iterable<ProfileModel> profiles, {
  required Set<String> blockedPubkeys,
}) {
  if (blockedPubkeys.isEmpty) {
    return profiles.toList(growable: false);
  }

  return profiles
      .where((profile) {
        final pubkey = profile.legacyPubkey?.trim();
        return pubkey == null ||
            pubkey.isEmpty ||
            !blockedPubkeys.contains(pubkey);
      })
      .toList(growable: false);
}

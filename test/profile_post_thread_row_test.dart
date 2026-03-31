import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/widgets/post_thread_row.dart';
import 'package:mobile/widgets/profile_post_thread_row.dart';

void main() {
  testWidgets(
    'ProfilePostThreadRow enables the edge-swipe media layout used on profile surfaces',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ProfilePostThreadRow(post: _post())),
        ),
      );

      final row = tester.widget<PostThreadRow>(find.byType(PostThreadRow));
      expect(row.useFeedEdgeSwipeMediaLayout, isTrue);
    },
  );
}

MediaPost _post() => MediaPost(
  id: 'post-id',
  pubkey: 'pubkey',
  contentHashes: const ['hash'],
  capturedAt: DateTime.utc(2026, 3, 29, 12),
  eventTags: const ['tokyo'],
  nostrEventId: 'nostr-post-id',
);

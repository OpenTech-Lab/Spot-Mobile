import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/event_model.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/profile_model.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/discover_screen.dart';

void main() {
  test('discoverFollowableTagForQuery normalizes hash-prefixed tags', () {
    expect(discoverFollowableTagForQuery('  #Test, '), 'test');
    expect(discoverFollowableTagForQuery('test'), isNull);
  });

  test('discoverSubmittedSearchQuery canonicalizes valid input', () {
    expect(discoverSubmittedSearchQuery('  #Test, '), '#test');
    expect(
      discoverSubmittedSearchQuery(' Fire near station '),
      'Fire near station',
    );
    expect(discoverSubmittedSearchQuery('   '), isNull);
    expect(discoverSubmittedSearchQuery('#'), isNull);
  });

  test('discover search result tabs are only used for keyword queries', () {
    expect(discoverSearchResultUsesTabbedLayout('smoke'), isTrue);
    expect(discoverSearchResultUsesTabbedLayout('#smoke'), isFalse);
    expect(discoverSearchResultUsesTabbedLayout('   '), isFalse);
  });

  test('discover search matches keyword in caption', () {
    final posts = [
      _post(id: '1', caption: 'Fire near station'),
      _post(id: '2', caption: 'Calm morning'),
    ];

    final visible = visibleDiscoverThreads(posts, query: 'fire');

    expect(visible.map((post) => post.id), ['1']);
  });

  test('discover search matches tags with leading hash syntax', () {
    final posts = [
      _post(id: '1', eventTags: const ['test']),
      _post(id: '2', eventTags: const ['weather']),
    ];

    final visible = visibleDiscoverThreads(posts, query: '#test');

    expect(visible.map((post) => post.id), ['1']);
  });

  test('discover search returns the root thread when a reply matches', () {
    final root = _post(
      id: 'root',
      nostrEventId: 'root-event',
      caption: 'Parent thread',
    );
    final reply = _post(
      id: 'reply',
      nostrEventId: 'reply-event',
      replyToId: 'root-event',
      caption: 'Witness saw smoke nearby',
    );
    final unrelated = _post(id: 'other', caption: 'Nothing relevant');

    final visible = visibleDiscoverThreads([
      root,
      reply,
      unrelated,
    ], query: 'smoke');

    expect(visible.map((post) => post.id), ['root']);
  });

  test('discover hides self-authored root threads when requested', () {
    final visible = visibleDiscoverThreads([
      _post(id: 'mine', pubkey: 'self'),
      _post(id: 'other', pubkey: 'other'),
    ], excludedAuthorPubkey: 'self');

    expect(visible.map((post) => post.id), ['other']);
  });

  test(
    'discover keeps other-authored roots even when my reply matches query',
    () {
      final root = _post(
        id: 'root',
        nostrEventId: 'root-event',
        pubkey: 'other',
        caption: 'Parent thread',
      );
      final myReply = _post(
        id: 'reply',
        nostrEventId: 'reply-event',
        pubkey: 'self',
        replyToId: 'root-event',
        caption: 'Smoke nearby',
      );

      final visible = visibleDiscoverThreads(
        [root, myReply],
        query: 'smoke',
        excludedAuthorPubkey: 'self',
      );

      expect(visible.map((post) => post.id), ['root']);
    },
  );

  testWidgets('keyword search results show threads and users tabs', (
    tester,
  ) async {
    final root = _post(id: 'root', caption: 'Smoke near station');
    final profile = ProfileModel(
      id: 'user-1',
      displayName: 'Citizen Jane',
      description: 'Tracks station reports',
      legacyPubkey:
          '2222222222222222222222222222222222222222222222222222222222222222',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoverSearchResultsScreen(
            wallet: _wallet(),
            initialQuery: 'smoke',
            initialPosts: [root],
            persistedPostsLoader: () async => const [],
            profileSearch: (_) async => [profile],
            eventStreamFactory: () => const Stream<CivicEvent>.empty(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('THREADS'), findsOneWidget);
    expect(find.text('USERS'), findsOneWidget);
    expect(find.text('Smoke near station'), findsOneWidget);

    await tester.tap(find.text('USERS'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Citizen Jane'), findsOneWidget);
    expect(find.text('Tracks station reports'), findsOneWidget);
  });

  testWidgets('hashtag search results keep a single thread pane', (
    tester,
  ) async {
    var profileSearchCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscoverSearchResultsScreen(
            wallet: _wallet(),
            initialQuery: '#fire',
            initialPosts: [
              _post(
                id: 'root',
                caption: 'Fire near station',
                eventTags: const ['fire'],
              ),
            ],
            persistedPostsLoader: () async => const [],
            profileSearch: (_) async {
              profileSearchCalls += 1;
              return const [];
            },
            eventStreamFactory: () => const Stream<CivicEvent>.empty(),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
    expect(find.text('Fire near station'), findsOneWidget);
    expect(profileSearchCalls, 0);
  });
}

MediaPost _post({
  required String id,
  String? pubkey,
  String? nostrEventId,
  String? replyToId,
  String? caption,
  List<String> eventTags = const ['general'],
  List<String> tags = const [],
}) => MediaPost(
  id: id,
  pubkey: pubkey ?? 'pubkey-$id',
  contentHashes: [id],
  capturedAt: DateTime.utc(2026, 3, 26),
  eventTags: eventTags,
  tags: tags,
  caption: caption,
  replyToId: replyToId,
  nostrEventId: nostrEventId ?? id,
);

WalletModel _wallet() => WalletModel(
  privateKeyHex:
      '0000000000000000000000000000000000000000000000000000000000000001',
  publicKeyHex:
      '1111111111111111111111111111111111111111111111111111111111111111',
  npub: 'npub1test',
  mnemonic: const ['test'],
  deviceId: 'device-1',
  isRevoked: false,
  createdAt: DateTime.utc(2026, 3, 29),
);

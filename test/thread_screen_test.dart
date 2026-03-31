import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/l10n/app_localizations.dart';
import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/thread_screen.dart';

void main() {
  test(
    'buildThreadScreenRoute uses a standard page route for thread detail',
    () {
      final route = buildThreadScreenRoute(
        rootPostId: 'post-id',
        initialPosts: [_post()],
        wallet: _wallet(),
      );

      expect(route, isA<MaterialPageRoute<void>>());
    },
  );

  test(
    'mergeThreadPostsWithPersistedState keeps cached media ready on reopen',
    () async {
      final mediaFile = File(
        '${Directory.systemTemp.path}/spot-thread-cached-${DateTime.now().microsecondsSinceEpoch}.mp4',
      );
      addTearDown(() async {
        if (mediaFile.existsSync()) {
          await mediaFile.delete();
        }
      });
      await mediaFile.writeAsBytes(const [0, 1, 2, 3]);

      final restored = await mergeThreadPostsWithPersistedState(
        initialPosts: [_post()],
        loadPersistedPosts: () async => [
          _post(mediaPaths: [mediaFile.path]),
        ],
      );

      expect(restored.single.mediaPaths, [mediaFile.path]);
      expect(postNeedsMediaHydration(restored.single), isFalse);
    },
  );

  testWidgets('thread detail route pops on a right-edge swipe gesture', (
    tester,
  ) async {
    final observer = _TestNavigatorObserver();

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [observer],
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                Navigator.of(context).push(
                  buildThreadScreenRoute(
                    rootPostId: 'post-id',
                    initialPosts: [_post(isTextOnly: true)],
                    wallet: _wallet(),
                    persistedPostsLoader: () async => const [],
                  ),
                );
              },
              child: const Text('Open thread'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open thread'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(ThreadScreen), findsOneWidget);

    final swipeRegion = find.byKey(threadScreenEdgeSwipeBackRegionKey);
    final gesture = await tester.startGesture(
      tester.getTopLeft(swipeRegion) + const Offset(12, 200),
    );
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(280, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(observer.popCount, 1);
  });
}

WalletModel _wallet() => WalletModel(
  privateKeyHex:
      '0000000000000000000000000000000000000000000000000000000000000001',
  publicKeyHex:
      '1111111111111111111111111111111111111111111111111111111111111111',
  npub: 'npub1test',
  mnemonic: const ['test'],
  deviceId: 'device-1',
  isRevoked: false,
  createdAt: DateTime.utc(2026, 3, 24),
);

MediaPost _post({
  List<String> mediaPaths = const [],
  bool isTextOnly = false,
}) => MediaPost(
  id: 'post-id',
  pubkey: 'pubkey',
  contentHashes: const ['post-id'],
  mediaPaths: mediaPaths,
  capturedAt: DateTime.utc(2026, 3, 24),
  eventTags: const ['tokyo'],
  isTextOnly: isTextOnly,
  nostrEventId: 'post-id',
);

class _TestNavigatorObserver extends NavigatorObserver {
  int popCount = 0;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    popCount += 1;
  }
}

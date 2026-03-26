import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/post_composer_screen.dart';

void main() {
  testWidgets('reply flow opens the same composer UI in reply mode', (
    tester,
  ) async {
    final wallet = _wallet();
    final replyTarget = _replyTarget(wallet.publicKeyHex);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () {
                showPostComposer(
                  context,
                  wallet: wallet,
                  replyToPost: replyTarget,
                  gpsLoader: () async => null,
                );
              },
              child: const Text('Reply'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Reply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.textContaining('Reply to'), findsOneWidget);
    expect(find.text('Write a reply…'), findsOneWidget);
    expect(find.text("What's happening?"), findsNothing);
  });

  testWidgets('options toggle dismisses the focused caption field', (
    tester,
  ) async {
    final wallet = _wallet();

    await tester.pumpWidget(_ComposerHarness(wallet: wallet));

    await tester.tap(find.text('Compose'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final captionField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == "What's happening?",
    );

    expect(captionField, findsOneWidget);
    await tester.tap(captionField);
    await tester.pump();

    expect(tester.widget<TextField>(captionField).focusNode?.hasFocus, isTrue);

    await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_3));
    await tester.pump();

    expect(tester.widget<TextField>(captionField).focusNode?.hasFocus, isFalse);
  });

  testWidgets('composer does not auto-focus the caption field on open', (
    tester,
  ) async {
    final wallet = _wallet();

    await tester.pumpWidget(_ComposerHarness(wallet: wallet));

    await tester.tap(find.text('Compose'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final captionField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == "What's happening?",
    );

    expect(captionField, findsOneWidget);
    expect(tester.widget<TextField>(captionField).focusNode?.hasFocus, isFalse);
  });

  testWidgets('tapping composer content dismisses the focused caption field', (
    tester,
  ) async {
    final wallet = _wallet();

    await tester.pumpWidget(_ComposerHarness(wallet: wallet));

    await tester.tap(find.text('Compose'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final captionField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.hintText == "What's happening?",
    );

    await tester.tap(captionField);
    await tester.pump();

    expect(tester.widget<TextField>(captionField).focusNode?.hasFocus, isTrue);

    await tester.tap(
      find.textContaining('First tag is the event category'),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(tester.widget<TextField>(captionField).focusNode?.hasFocus, isFalse);
  });

  testWidgets('composer content scroll view dismisses keyboard on drag', (
    tester,
  ) async {
    final wallet = _wallet();

    await tester.pumpWidget(_ComposerHarness(wallet: wallet));

    await tester.tap(find.text('Compose'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final scrollView = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView).first,
    );

    expect(
      scrollView.keyboardDismissBehavior,
      ScrollViewKeyboardDismissBehavior.onDrag,
    );
  });

  testWidgets(
    'category tag uses the trailing create button and still accepts enter',
    (tester) async {
      final wallet = _wallet();

      await tester.pumpWidget(_ComposerHarness(wallet: wallet));

      await tester.tap(find.text('Compose'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final categoryField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.hintText ==
                'Category tag (e.g. AWSSummitTokyo2026)',
      );

      await tester.enterText(categoryField, 'tokyo,');
      await tester.pump();

      expect(find.text('#tokyo'), findsNothing);

      await tester.tap(find.byIcon(CupertinoIcons.plus_circle_fill));
      await tester.pump();

      expect(find.text('#tokyo'), findsOneWidget);

      await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
      await tester.pump();

      await tester.enterText(categoryField, 'shibuya');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      expect(find.text('#shibuya'), findsOneWidget);
    },
  );
}

class _ComposerHarness extends StatelessWidget {
  const _ComposerHarness({required this.wallet});

  final WalletModel wallet;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () {
              showPostComposer(
                context,
                wallet: wallet,
                gpsLoader: () async => null,
              );
            },
            child: const Text('Compose'),
          ),
        ),
      ),
    );
  }
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
  createdAt: DateTime.utc(2026, 3, 23),
);

MediaPost _replyTarget(String pubkey) => MediaPost(
  id: 'reply-target-id',
  pubkey: pubkey,
  contentHashes: const ['reply-target-id'],
  capturedAt: DateTime.utc(2026, 3, 23, 12),
  eventTags: const ['tokyo'],
  caption: 'Original thread',
  nostrEventId: 'reply-target-id',
);

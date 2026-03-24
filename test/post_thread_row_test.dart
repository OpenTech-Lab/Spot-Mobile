import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';

void main() {
  test('visibleThreadTagsForPost hides inline tags on root posts', () {
    final post = _post(eventTags: const ['tokyo', 'news', 'urgent']);

    expect(visibleThreadTagsForPost(post), isEmpty);
  });

  test('visibleThreadTagsForPost shows only sub tags on replies', () {
    final post = _post(
      eventTags: const ['tokyo', 'news', 'urgent'],
      replyToId: 'root-id',
    );

    expect(visibleThreadTagsForPost(post), ['news', 'urgent']);
  });

  test('visibleThreadTagsForPost hides category-only tags on replies', () {
    final post = _post(eventTags: const ['tokyo'], replyToId: 'root-id');

    expect(visibleThreadTagsForPost(post), isEmpty);
  });

  test('visibleThreadLocationTextForPost shows hidden label without GPS', () {
    final post = _post(eventTags: const ['tokyo']);
    final location = visibleThreadLocationTextForPost(post);

    expect(location, 'Location hidden');
  });

  test('visibleThreadLocationTextForPost shows virtual label', () {
    final post = _post(eventTags: const ['tokyo'], isVirtual: true);
    final location = visibleThreadLocationTextForPost(post);

    expect(location, 'Virtual');
  });

  test(
    'visibleThreadLocationTextForPost shows spot name and place for check-ins',
    () {
      final post = _post(
        eventTags: const ['tokyo'],
        latitude: 35.7,
        longitude: 139.7,
        spotName: 'Shibuya Crossing',
      );
      final location = visibleThreadLocationTextForPost(
        post,
        geoLocation: const GeoLocation(city: 'Tokyo', country: 'Japan'),
      );

      expect(location, 'Shibuya Crossing - Japan/Tokyo (35.7, 139.7)');
    },
  );

  test(
    'visibleThreadLocationTextForPost shows place only for normal geo posts',
    () {
      final post = _post(
        eventTags: const ['tokyo'],
        latitude: 35.6895,
        longitude: 139.6917,
      );
      final location = visibleThreadLocationTextForPost(
        post,
        geoLocation: const GeoLocation(city: 'Tokyo', country: 'Japan'),
      );

      expect(location, 'Japan/Tokyo');
    },
  );

  test(
    'visibleThreadLocationTextForPost falls back to coarse coordinates without geo lookup',
    () {
      final post = _post(
        eventTags: const ['tokyo'],
        latitude: 35.6895,
        longitude: 139.6917,
      );
      final location = visibleThreadLocationTextForPost(post);

      expect(location, '35.7, 139.7');
    },
  );

  testWidgets('PostThreadRow shows hidden location once in the location row', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostThreadRow(
            post: _post(eventTags: const ['tokyo']),
            isLast: true,
          ),
        ),
      ),
    );

    expect(find.text('Location hidden'), findsOneWidget);
  });

  testWidgets('PostThreadRow shows category tag in the header only once', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostThreadRow(
            post: _post(eventTags: const ['tokyo', 'news']),
            isLast: true,
          ),
        ),
      ),
    );

    expect(find.textContaining('#tokyo'), findsOneWidget);
  });

  testWidgets(
    'PostThreadRow shows full spot location between body and actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostThreadRow(
              post: _post(
                eventTags: const ['tokyo'],
                latitude: 35.7,
                longitude: 139.7,
                spotName: 'Shibuya Crossing',
              ),
              isLast: true,
            ),
          ),
        ),
      );

      expect(find.text('Shibuya Crossing - 35.7, 139.7'), findsOneWidget);
    },
  );

  testWidgets('PostThreadRow does not overflow on narrow widths', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 240,
              child: PostThreadRow(
                post: _post(
                  eventTags: const ['very-long-category-name', 'news'],
                  latitude: 35.6895,
                  longitude: 139.6917,
                ),
                isLast: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('PostThreadRow shows zero counts for reply and like by default', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostThreadRow(
            post: _post(
              eventTags: const ['tokyo'],
              replyCount: 0,
              likeCount: 0,
            ),
            isLast: true,
          ),
        ),
      ),
    );

    expect(find.text('0'), findsNWidgets(2));
  });

  testWidgets('PostThreadRow like button turns red and increments count', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: _LikeHarness(post: _post(eventTags: const ['tokyo'])),
        ),
      ),
    );

    expect(find.byIcon(Icons.favorite_border), findsNothing);
    expect(find.byIcon(CupertinoIcons.heart), findsOneWidget);
    expect(find.text('1'), findsNothing);

    await tester.tap(find.byIcon(CupertinoIcons.heart));
    await tester.pump();

    final icon = tester.widget<Icon>(find.byIcon(CupertinoIcons.heart_fill));
    final count = tester.widget<Text>(find.text('1'));

    expect(icon.color, SpotColors.danger);
    expect(count.style?.color, SpotColors.danger);
  });

  testWidgets('PostThreadRow shows loading hint while preview media hydrates', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              PostThreadRow(
                post: _post(
                  eventTags: const ['tokyo'],
                  previewBase64: _tinyPngBase64,
                  previewMimeType: 'image/png',
                ),
                isLast: true,
                isMediaLoading: true,
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Loading full image…'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
  });
}

MediaPost _post({
  required List<String> eventTags,
  String? replyToId,
  double? latitude,
  double? longitude,
  bool isVirtual = false,
  String? spotName,
  int replyCount = 0,
  int likeCount = 0,
  bool isLikedByMe = false,
  String? previewBase64,
  String? previewMimeType,
}) => MediaPost(
  id: 'post-id',
  pubkey: 'pubkey',
  contentHashes: const ['post-id'],
  capturedAt: DateTime.utc(2026, 3, 23),
  eventTags: eventTags,
  replyToId: replyToId,
  latitude: latitude,
  longitude: longitude,
  isVirtual: isVirtual,
  spotName: spotName,
  replyCount: replyCount,
  likeCount: likeCount,
  isLikedByMe: isLikedByMe,
  previewBase64: previewBase64,
  previewMimeType: previewMimeType,
  nostrEventId: 'post-id',
);

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a8Z0AAAAASUVORK5CYII=';

class _LikeHarness extends StatefulWidget {
  const _LikeHarness({required this.post});

  final MediaPost post;

  @override
  State<_LikeHarness> createState() => _LikeHarnessState();
}

class _LikeHarnessState extends State<_LikeHarness> {
  late MediaPost _post;

  @override
  void initState() {
    super.initState();
    _post = widget.post;
  }

  @override
  Widget build(BuildContext context) {
    return PostThreadRow(
      post: _post,
      isLast: true,
      onLike: () {
        setState(() {
          _post = _post.copyWith(isLikedByMe: !_post.isLikedByMe);
        });
      },
    );
  }
}

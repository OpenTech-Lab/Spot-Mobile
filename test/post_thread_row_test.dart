import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/models/media_post.dart';
import 'package:mobile/services/geo_lookup.dart';
import 'package:mobile/theme/spot_theme.dart';
import 'package:mobile/widgets/post_thread_row.dart';
import 'package:mobile/widgets/profile_avatar.dart';

void main() {
  test(
    'postThreadRowFeedTwoImageWidth keeps the gap and preserves full left reach',
    () {
      const viewportWidth = 306.0;
      final itemWidth = postThreadRowFeedTwoImageWidth(viewportWidth);
      final contentWidth = (itemWidth * 2) + postThreadRowMediaGap;
      final expandedViewportWidth =
          viewportWidth + postThreadRowFeedMediaSwipeLeftBleed;
      final maxScrollExtent = contentWidth - expandedViewportWidth;

      expect(postThreadRowMediaGap, 6);
      expect(itemWidth, greaterThan(200));
      expect(
        maxScrollExtent,
        greaterThanOrEqualTo(
          postThreadRowFeedMediaSwipeLeftBleed +
              postThreadRowFeedMediaSwipeActivationThreshold,
        ),
      );
    },
  );

  test('visibleThreadTagsForPost shows only sub tags on root posts', () {
    final post = _post(eventTags: const ['tokyo', 'news', 'urgent']);

    expect(visibleThreadTagsForPost(post), ['news', 'urgent']);
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

  test('visibleThreadTagsForPost hides category-only tags on root posts', () {
    final post = _post(eventTags: const ['tokyo']);

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

  testWidgets('PostThreadRow shows extra tags below the media block', (
    tester,
  ) async {
    final mediaPaths = _createTempMediaPaths(count: 1);
    addTearDown(() => _cleanupTempMediaPaths(mediaPaths));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostThreadRow(
            post: _post(
              eventTags: const ['tokyo', 'news', 'urgent'],
              mediaPaths: mediaPaths,
            ),
            isLast: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('#tokyo'), findsOneWidget);
    expect(find.text('#news'), findsOneWidget);
    expect(find.text('#urgent'), findsOneWidget);

    final mediaRect = tester.getRect(find.byType(Image).first);
    final tagRect = tester.getRect(find.text('#news'));

    expect(tagRect.top, greaterThan(mediaRect.bottom));
  });

  testWidgets(
    'PostThreadRow keeps secondhand posts icon-only without the text badge',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostThreadRow(
              post: _post(
                eventTags: const ['tokyo'],
                sourceType: PostSourceType.secondhand,
              ),
              isLast: true,
            ),
          ),
        ),
      );

      expect(find.text('2nd hand'), findsNothing);

      final icon = tester.widget<Icon>(
        find.byIcon(CupertinoIcons.arrow_2_squarepath),
      );
      expect(icon.color, SpotColors.accent);
    },
  );

  testWidgets(
    'PostThreadRow shows author display name and passes avatar hash through',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostThreadRow(
              post: _post(
                eventTags: const ['tokyo'],
                authorDisplayName: 'Citizen Tokyo',
                authorAvatarContentHash: 'avatar-hash-1',
              ),
              isLast: true,
            ),
          ),
        ),
      );

      expect(find.text('Citizen Tokyo'), findsOneWidget);
      expect(find.textContaining('pubkey'), findsNothing);

      final avatar = tester.widget<ProfileAvatar>(find.byType(ProfileAvatar));
      expect(avatar.avatarContentHash, 'avatar-hash-1');
    },
  );

  testWidgets('PostThreadRow calls onTagTap for the category tag', (
    tester,
  ) async {
    String? tappedTag;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostThreadRow(
            post: _post(eventTags: const ['tokyo', 'news']),
            isLast: true,
            onTagTap: (tag) => tappedTag = tag,
          ),
        ),
      ),
    );

    await tester.tap(find.text('#tokyo'));
    await tester.pump();

    expect(tappedTag, 'tokyo');
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

  testWidgets('PostThreadRow auto-requests missing media on first build', (
    tester,
  ) async {
    var updateCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListView(
            children: [
              PostThreadRow(
                post: _post(eventTags: const ['tokyo']),
                isLast: true,
                onMediaUpdated: (_) => updateCalls++,
              ),
            ],
          ),
        ),
      ),
    );

    await tester.pump();

    expect(updateCalls, 1);

    await tester.pump();
    expect(updateCalls, 1);
  });

  testWidgets(
    'PostThreadRow feed media keeps the default inset gap before swiping',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final mediaPaths = _createTempMediaPaths(count: 3);
      addTearDown(() => _cleanupTempMediaPaths(mediaPaths));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostThreadRow(
              post: _post(eventTags: const ['tokyo'], mediaPaths: mediaPaths),
              isLast: true,
              useFeedEdgeSwipeMediaLayout: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewport = find.byKey(postThreadRowMediaViewportKey);
      final left = tester.getTopLeft(viewport).dx;

      expect(left, closeTo(postThreadRowFeedMediaSwipeLeftBleed, 0.1));
    },
  );

  testWidgets(
    'PostThreadRow feed media widens with slider progress and keeps later images expanded',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final mediaPaths = _createTempMediaPaths(count: 3);
      addTearDown(() => _cleanupTempMediaPaths(mediaPaths));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostThreadRow(
              post: _post(eventTags: const ['tokyo'], mediaPaths: mediaPaths),
              isLast: true,
              useFeedEdgeSwipeMediaLayout: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final viewport = find.byKey(postThreadRowMediaViewportKey);
      final mediaContent = find.byKey(postThreadRowMediaContentKey);
      final mediaImage = find.byType(Image).first;

      final idleLeft = tester.getTopLeft(viewport).dx;
      final idleWidth = tester.getSize(mediaContent).width;
      await tester.drag(mediaImage, const Offset(-40, 0));
      await tester.pumpAndSettle();

      final partialSwipeWidth = tester.getSize(mediaContent).width;
      expect(idleLeft, closeTo(postThreadRowFeedMediaSwipeLeftBleed, 0.1));
      expect(partialSwipeWidth, greaterThan(idleWidth));
      expect(
        partialSwipeWidth,
        lessThan(idleWidth + postThreadRowFeedMediaSwipeLeftBleed),
      );

      await tester.drag(mediaImage, const Offset(-240, 0));
      await tester.pumpAndSettle();

      final fullSwipeWidth = tester.getSize(mediaContent).width;
      expect(
        fullSwipeWidth,
        closeTo(idleWidth + postThreadRowFeedMediaSwipeLeftBleed, 0.1),
      );

      await tester.drag(mediaContent, const Offset(320, 0));
      await tester.pumpAndSettle();

      final resetWidth = tester.getSize(mediaContent).width;
      expect(resetWidth, closeTo(idleWidth, 0.1));
    },
  );

  testWidgets(
    'PostThreadRow two-image feed media still reaches the left edge',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final mediaPaths = _createTempMediaPaths(count: 2);
      addTearDown(() => _cleanupTempMediaPaths(mediaPaths));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PostThreadRow(
              post: _post(eventTags: const ['tokyo'], mediaPaths: mediaPaths),
              isLast: true,
              useFeedEdgeSwipeMediaLayout: true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final mediaContent = find.byKey(postThreadRowMediaContentKey);

      expect(
        tester.getTopLeft(mediaContent).dx,
        closeTo(postThreadRowFeedMediaSwipeLeftBleed, 0.1),
      );

      final idleWidth = tester.getSize(mediaContent).width;
      await tester.drag(mediaContent, const Offset(-240, 0));
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(mediaContent).dx, closeTo(0, 0.1));
      expect(
        tester.getSize(mediaContent).width,
        closeTo(idleWidth + postThreadRowFeedMediaSwipeLeftBleed, 0.1),
      );
    },
  );
}

MediaPost _post({
  required List<String> eventTags,
  List<String>? mediaPaths,
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
  String? authorDisplayName,
  String? authorAvatarContentHash,
  PostSourceType sourceType = PostSourceType.firsthand,
}) => MediaPost(
  id: 'post-id',
  pubkey: 'pubkey',
  authorDisplayName: authorDisplayName,
  authorAvatarContentHash: authorAvatarContentHash,
  contentHashes: mediaPaths == null
      ? const ['post-id']
      : List<String>.generate(mediaPaths.length, (index) => 'post-id-$index'),
  mediaPaths: mediaPaths ?? const [],
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
  sourceType: sourceType,
  nostrEventId: 'post-id',
);

const _tinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a8Z0AAAAASUVORK5CYII=';

List<String> _createTempMediaPaths({required int count}) {
  final bytes = base64Decode(_tinyPngBase64);
  final directory = Directory.systemTemp.createTempSync('post-thread-row-test');
  final paths = <String>[];
  for (var index = 0; index < count; index++) {
    final file = File('${directory.path}/media-$index.png');
    file.writeAsBytesSync(bytes);
    paths.add(file.path);
  }
  return paths;
}

void _cleanupTempMediaPaths(List<String> paths) {
  final directories = <String>{};
  for (final path in paths) {
    final file = File(path);
    directories.add(file.parent.path);
    if (file.existsSync()) {
      file.deleteSync();
    }
  }
  for (final directoryPath in directories) {
    final directory = Directory(directoryPath);
    if (directory.existsSync()) {
      directory.deleteSync(recursive: true);
    }
  }
}

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

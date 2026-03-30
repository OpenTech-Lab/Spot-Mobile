import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/services/cdn_media_service.dart';

void main() {
  test('runtime CDN base URL wins over compile-time value', () {
    final resolved = CdnMediaService.resolveCdnBaseUrl(
      compileValue: 'https://compile.example',
      runtimeValue: 'https://runtime.example',
    );

    expect(resolved, 'https://runtime.example');
  });

  test('runtime presign URL wins over compile-time value', () {
    final resolved = CdnMediaService.resolvePresignEndpoint(
      compileValue: 'https://compile-presign.example',
      runtimeValue: 'https://runtime-presign.example',
    );

    expect(resolved, 'https://runtime-presign.example');
  });

  test('CDN base URL falls back to production CloudFront when unset', () {
    final resolved = CdnMediaService.resolveCdnBaseUrl(
      compileValue: '',
      runtimeValue: '',
    );

    expect(resolved, 'https://d3ttkxcceqn0cp.cloudfront.net');
  });

  test(
    'presign URL stays empty when both runtime and compile values are unset',
    () {
      final resolved = CdnMediaService.resolvePresignEndpoint(
        compileValue: '',
        runtimeValue: '',
      );

      expect(resolved, isEmpty);
    },
  );

  test('timestamp drift error body is detected from JSON response', () {
    expect(
      CdnMediaService.isTimestampDriftResponseBody(
        '{"error":"Timestamp too far from server time"}',
      ),
      isTrue,
    );
  });

  test('timestamp drift detector ignores unrelated errors', () {
    expect(
      CdnMediaService.isTimestampDriftResponseBody(
        '{"error":"Invalid signature"}',
      ),
      isFalse,
    );
  });

  test('HTTP date header parses to epoch seconds', () {
    final seconds = CdnMediaService.timestampSecondsFromDateHeader(
      'Mon, 30 Mar 2026 12:34:56 GMT',
    );

    expect(seconds, isNotNull);
    expect(
      DateTime.fromMillisecondsSinceEpoch(seconds! * 1000, isUtc: true),
      DateTime.utc(2026, 3, 30, 12, 34, 56),
    );
  });
}

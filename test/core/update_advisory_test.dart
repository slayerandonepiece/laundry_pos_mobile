import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:myshop/core/gate/update_advisory.dart';
import 'package:myshop/core/network/dio_interceptors.dart';

import '../helpers/mock_dio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => UpdateAdvisory.level.value = UpdateLevel.none);

  group('UpdateAdvisory.parse', () {
    test('maps known values, ignoring case and spaces', () {
      expect(UpdateAdvisory.parse('soft'), UpdateLevel.soft);
      expect(UpdateAdvisory.parse(' URGENT '), UpdateLevel.urgent);
      expect(UpdateAdvisory.parse('none'), UpdateLevel.none);
    });

    test('unknown or missing means no information', () {
      expect(UpdateAdvisory.parse(null), isNull);
      expect(UpdateAdvisory.parse(''), isNull);
      expect(UpdateAdvisory.parse('banana'), isNull);
    });
  });

  group('UpdateAdvisory.nextOffer', () {
    UpdateLevel? offer(
      UpdateLevel level, {
      bool flowActive = false,
      bool softOffered = false,
      bool urgentOffered = false,
      bool safeMoment = true,
    }) => UpdateAdvisory.nextOffer(
      level: level,
      flowActive: flowActive,
      softOffered: softOffered,
      urgentOffered: urgentOffered,
      safeMoment: safeMoment,
    );

    test('offers the advertised level at a safe moment', () {
      expect(offer(UpdateLevel.soft), UpdateLevel.soft);
      expect(offer(UpdateLevel.urgent), UpdateLevel.urgent);
    });

    test('offers nothing at level none', () {
      expect(offer(UpdateLevel.none), isNull);
    });

    test('waits while a sale or an open form makes it unsafe', () {
      expect(offer(UpdateLevel.urgent, safeMoment: false), isNull);
      expect(offer(UpdateLevel.soft, safeMoment: false), isNull);
    });

    test('offers each level once, and never while a prompt is showing', () {
      expect(offer(UpdateLevel.soft, softOffered: true), isNull);
      expect(offer(UpdateLevel.urgent, urgentOffered: true), isNull);
      expect(offer(UpdateLevel.urgent, flowActive: true), isNull);
    });

    test('a soft offer does not block a later urgent one', () {
      expect(offer(UpdateLevel.urgent, softOffered: true), UpdateLevel.urgent);
    });
  });

  group('UpdateAdvisory.compareVersions', () {
    test('compares numerically, not as text', () {
      expect(UpdateAdvisory.compareVersions('1.10.0', '1.9.0'), 1);
      expect(UpdateAdvisory.compareVersions('1.0.0', '1.0.1'), -1);
      expect(UpdateAdvisory.compareVersions('1.2', '1.2.0'), 0);
      expect(UpdateAdvisory.compareVersions(' 2 ', '1.9.9'), 1);
    });

    test('anything unreadable is unknown, never an answer', () {
      expect(UpdateAdvisory.compareVersions(null, '1.0.0'), isNull);
      expect(UpdateAdvisory.compareVersions('1.0.0', null), isNull);
      expect(UpdateAdvisory.compareVersions('1.0.0+2', '1.0.0'), isNull);
      expect(UpdateAdvisory.compareVersions('x.y', '1.0.0'), isNull);
    });
  });

  group('UpdateAdvisory.effectiveLevel', () {
    UpdateLevel effective(UpdateLevel level, String? min, String? installed) =>
        UpdateAdvisory.effectiveLevel(
          level: level,
          minVersion: min,
          installedVersion: installed,
        );

    test('an install below the minimum keeps the backend level', () {
      expect(
        effective(UpdateLevel.urgent, '1.0.1', '1.0.0'),
        UpdateLevel.urgent,
      );
      expect(effective(UpdateLevel.soft, '1.1.0', '1.0.9'), UpdateLevel.soft);
    });

    test('an install at or above the minimum is never blocked or prompted', () {
      expect(effective(UpdateLevel.urgent, '1.0.1', '1.0.1'), UpdateLevel.none);
      expect(effective(UpdateLevel.urgent, '1.0.1', '1.2.0'), UpdateLevel.none);
      expect(effective(UpdateLevel.soft, '1.1.0', '2.0.0'), UpdateLevel.none);
    });

    test('when a version cannot be read, the backend level stands', () {
      expect(effective(UpdateLevel.urgent, null, '1.0.0'), UpdateLevel.urgent);
      expect(effective(UpdateLevel.urgent, '1.0.1', null), UpdateLevel.urgent);
      expect(
        effective(UpdateLevel.urgent, 'junk', '1.0.0'),
        UpdateLevel.urgent,
      );
    });

    test('none stays none', () {
      expect(effective(UpdateLevel.none, '1.0.1', '0.0.1'), UpdateLevel.none);
    });
  });

  group('UpdateAdvisory.record', () {
    setUp(() => UpdateAdvisory.latestMinVersion = null);

    test('keeps the minimum with the level that named it', () {
      UpdateAdvisory.record('urgent', ' 1.0.1 ');
      expect(UpdateAdvisory.level.value, UpdateLevel.urgent);
      expect(UpdateAdvisory.latestMinVersion, '1.0.1');
    });

    test('none drops the minimum', () {
      UpdateAdvisory.record('urgent', '1.0.1');
      UpdateAdvisory.record('none', '1.0.1');
      expect(UpdateAdvisory.latestMinVersion, isNull);
    });

    test('a reply without a level changes nothing, minimum included', () {
      UpdateAdvisory.record('urgent', '1.0.1');
      UpdateAdvisory.record(null, '9.9.9');
      expect(UpdateAdvisory.level.value, UpdateLevel.urgent);
      expect(UpdateAdvisory.latestMinVersion, '1.0.1');
    });
  });

  group('UpdateAdvisory.probe', () {
    setUp(() {
      UpdateAdvisory.level.value = UpdateLevel.none;
      UpdateAdvisory.latestMinVersion = null;
    });

    test(
      'learns the level from a 401 reply, without touching the session',
      () async {
        await UpdateAdvisory.probe(
          dio: createMockDio(
            (_) => mockJsonResponse(
              {'error': 'Unauthorized'},
              statusCode: 401,
              headers: {
                UpdateAdvisory.levelHeader: ['urgent'],
                UpdateAdvisory.minVersionHeader: ['1.0.1'],
              },
            ),
          ),
        );
        expect(UpdateAdvisory.level.value, UpdateLevel.urgent);
        expect(UpdateAdvisory.latestMinVersion, '1.0.1');
      },
    );

    test('hears that the level was lowered', () async {
      UpdateAdvisory.level.value = UpdateLevel.urgent;
      UpdateAdvisory.latestMinVersion = '1.0.1';
      await UpdateAdvisory.probe(
        dio: createMockDio(
          (_) => mockJsonResponse(
            {'ok': true},
            headers: {
              UpdateAdvisory.levelHeader: ['none'],
            },
          ),
        ),
      );
      expect(UpdateAdvisory.level.value, UpdateLevel.none);
      expect(UpdateAdvisory.latestMinVersion, isNull);
    });

    test(
      'a reply without a level, or no connection, changes nothing',
      () async {
        UpdateAdvisory.level.value = UpdateLevel.urgent;
        await UpdateAdvisory.probe(
          dio: createMockDio((_) => mockJsonResponse({'ok': true})),
        );
        expect(UpdateAdvisory.level.value, UpdateLevel.urgent);

        await UpdateAdvisory.probe(
          dio: createMockDio((o) => throw DioException(requestOptions: o)),
        );
        expect(UpdateAdvisory.level.value, UpdateLevel.urgent);
      },
    );
  });

  group('UpdateAdvisoryInterceptor', () {
    Dio dioReplying(int status, {String? level}) => createMockDio(
      (_) => mockJsonResponse(
        {'ok': true},
        statusCode: status,
        headers: {
          if (level != null) UpdateAdvisory.levelHeader: [level],
        },
      ),
    )..interceptors.add(UpdateAdvisoryInterceptor());

    test('records the level from a successful response', () async {
      await dioReplying(200, level: 'urgent').get('https://x.test/a');
      expect(UpdateAdvisory.level.value, UpdateLevel.urgent);
    });

    test('records the level even when the request fails', () async {
      await expectLater(
        dioReplying(500, level: 'soft').get('https://x.test/a'),
        throwsA(isA<DioException>()),
      );
      expect(UpdateAdvisory.level.value, UpdateLevel.soft);
    });

    test('a reply without the header keeps the known level', () async {
      UpdateAdvisory.level.value = UpdateLevel.soft;
      await dioReplying(200).get('https://x.test/a');
      expect(UpdateAdvisory.level.value, UpdateLevel.soft);
    });

    test(
      'ticks on every response with a level, even an unchanged one',
      () async {
        UpdateAdvisory.level.value = UpdateLevel.soft;
        final before = UpdateAdvisory.responses.value;
        await dioReplying(200, level: 'soft').get('https://x.test/a');
        await dioReplying(200, level: 'soft').get('https://x.test/a');
        expect(UpdateAdvisory.responses.value, before + 2);
        await dioReplying(200).get('https://x.test/a'); // no header: no tick
        expect(UpdateAdvisory.responses.value, before + 2);
      },
    );

    test('reads the minimum version from success and error replies', () async {
      Dio dioWithMin(int status) => createMockDio(
        (_) => mockJsonResponse(
          {'ok': true},
          statusCode: status,
          headers: {
            UpdateAdvisory.levelHeader: ['urgent'],
            UpdateAdvisory.minVersionHeader: ['1.0.1'],
          },
        ),
      )..interceptors.add(UpdateAdvisoryInterceptor());

      UpdateAdvisory.latestMinVersion = null;
      await dioWithMin(200).get('https://x.test/a');
      expect(UpdateAdvisory.latestMinVersion, '1.0.1');

      UpdateAdvisory.latestMinVersion = null;
      await expectLater(
        dioWithMin(500).get('https://x.test/a'),
        throwsA(isA<DioException>()),
      );
      expect(UpdateAdvisory.latestMinVersion, '1.0.1');
    });

    test('never changes the response a caller receives', () async {
      final response = await dioReplying(
        200,
        level: 'urgent',
      ).get('https://x.test/a');
      expect(response.statusCode, 200);
      expect(response.data, {'ok': true});
    });
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'package:app16_lowest/models/market_event.dart';
import 'package:app16_lowest/models/temp_outcome_bucket.dart';
import 'package:app16_lowest/services/station_temperature_api.dart';

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
  });

  group('parseTempOutcomeBucket', () {
    test('exact C and F', () {
      final c = parseTempOutcomeBucket('26°C');
      expect(c?.kind, TempBucketKind.exact);
      expect(c?.exact, 26);
      expect(c?.unit, 'C');

      final f = parseTempOutcomeBucket('50F');
      expect(f?.kind, TempBucketKind.exact);
      expect(f?.exact, 50);
      expect(f?.unit, 'F');
    });

    test('or below', () {
      final b = parseTempOutcomeBucket('20°C or below');
      expect(b?.kind, TempBucketKind.orBelow);
      expect(b?.exact, 20);
    });

    test('range', () {
      final b = parseTempOutcomeBucket('50-51°F');
      expect(b?.kind, TempBucketKind.range);
      expect(b?.lo, 50);
      expect(b?.hi, 51);
      expect(b?.unit, 'F');
    });
  });

  group('isPhysicsDeadOutcome', () {
    test('exact warmer than obs min is dead', () {
      final exact18 = parseTempOutcomeBucket('18°C')!;
      expect(isPhysicsDeadOutcome(exact18, 17), isTrue);
      expect(isPhysicsDeadOutcome(exact18, 18), isFalse);
      expect(isPhysicsDeadOutcome(exact18, 18.5), isFalse);
    });

    test('or below never dead from observed alone', () {
      final floor = parseTempOutcomeBucket('16°C or below')!;
      expect(isPhysicsDeadOutcome(floor, 20), isFalse);
      expect(isPhysicsDeadOutcome(floor, 10), isFalse);
    });

    test('range dead when obs already below lo', () {
      final range = parseTempOutcomeBucket('50-51°F')!;
      expect(isPhysicsDeadOutcome(range, 49), isTrue);
      expect(isPhysicsDeadOutcome(range, 50), isFalse);
      expect(isPhysicsDeadOutcome(range, 50.5), isFalse);
    });
  });

  group('leadingSettlementBucket', () {
    OutcomeMarket m(String label) => OutcomeMarket(
          id: label,
          question: label,
          groupItemTitle: label,
          outcomes: const ['Yes', 'No'],
          outcomePrices: const [0.5, 0.5],
          volume: 0,
        );

    test('picks exact degree containing obs min', () {
      final leading = leadingSettlementBucket(
        [m('17°C'), m('18°C'), m('16°C or below')],
        17,
      );
      expect(leading?.label, '17°C');
    });

    test('falls back to or-below when colder', () {
      final leading = leadingSettlementBucket(
        [m('18°C'), m('16°C or below')],
        15,
      );
      expect(leading?.kind, TempBucketKind.orBelow);
      expect(leading?.exact, 16);
    });
  });

  group('series mins', () {
    test('observed and forecast remaining mins', () {
      final loc = tz.getLocation('Asia/Shanghai');
      final dayStart = tz.TZDateTime(loc, 2026, 9, 6);
      final dayEnd = dayStart.add(const Duration(days: 1));
      final now = tz.TZDateTime(loc, 2026, 9, 6, 12);
      final series = DailyTemperatureSeries(
        siteId: 'ZSJN',
        unit: 'C',
        dayStart: dayStart,
        dayEnd: dayEnd,
        nowLocal: now,
        points: [
          HourlyTempPoint(
            localHourStart: tz.TZDateTime(loc, 2026, 9, 6, 5),
            temperature: 17,
            kind: TempPointKind.observed,
            isDailyMinimum: true,
          ),
          HourlyTempPoint(
            localHourStart: tz.TZDateTime(loc, 2026, 9, 6, 10),
            temperature: 22,
            kind: TempPointKind.observed,
          ),
          HourlyTempPoint(
            localHourStart: tz.TZDateTime(loc, 2026, 9, 6, 14),
            temperature: 19,
            kind: TempPointKind.forecast,
          ),
          HourlyTempPoint(
            localHourStart: tz.TZDateTime(loc, 2026, 9, 6, 18),
            temperature: 18,
            kind: TempPointKind.forecast,
          ),
        ],
      );
      expect(seriesObservedMin(series), 17);
      expect(seriesForecastRemainingMin(series), 18);
    });
  });
}

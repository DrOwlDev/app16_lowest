import 'package:flutter_test/flutter_test.dart';

import 'package:app16_lowest/main.dart';
import 'package:app16_lowest/models/market_event.dart';
import 'package:app16_lowest/services/city_timezones.dart';

void main() {
  setUpAll(CityTimezones.ensureInitialized);

  testWidgets('Low Temp app shows search', (WidgetTester tester) async {
    await tester.pumpWidget(const LowTempApp());
    expect(find.text('Search city…'), findsOneWidget);
    expect(find.textContaining('Min conv'), findsOneWidget);
  });

  test('MarketEvent parses nested stringified outcomes', () {
    final event = MarketEvent.fromJson({
      'id': '1',
      'title': 'Lowest temperature in Hong Kong on September 5?',
      'slug': 'lowest-temperature-in-hong-kong-on-september-5-2026',
      'volume': 1000,
      'volume24hr': 500,
      'endDate': '2026-09-05T12:00:00Z',
      'markets': [
        {
          'id': '10',
          'question': '26°C?',
          'groupItemTitle': '26°C',
          'outcomes': '["Yes", "No"]',
          'outcomePrices': '["0.61", "0.39"]',
          'volumeNum': 100,
          'bestAsk': 0.62,
          'bestBid': 0.58,
          'clobTokenIds': '["111", "222"]',
        },
        {
          'id': '11',
          'question': '20°C?',
          'groupItemTitle': '20°C or below',
          'outcomes': '["Yes", "No"]',
          'outcomePrices': '["0", "1"]',
          'volumeNum': 50,
        },
      ],
    });

    expect(event.title, contains('Hong Kong'));
    expect(event.cityName, 'Hong Kong');
    expect(event.leadingYesPrice, closeTo(0.62, 0.001));
    expect(event.markets, hasLength(2));
    expect(event.markets.first.outcomes, ['Yes', 'No']);
    expect(event.markets.first.yesPrice, closeTo(0.61, 0.001));
    expect(event.markets.first.buyYesPrice, closeTo(0.62, 0.001));
    expect(event.markets.first.displayChance, closeTo(0.62, 0.001));
    expect(event.markets.first.buyNoPrice, closeTo(0.42, 0.001));
    expect(formatBuyCents(0.004), '0.4¢');
    expect(formatBuyCents(null), '--');
    expect(formatBuyCents(event.markets[1].buyYesPrice), '--');
    expect(formatBuyCents(event.markets[1].buyNoPrice), '--');
    expect(event.markets[1].bothBuysInactive, isTrue);
    expect(event.localEndOfDay, isNotNull);
    expect(
      formatTimeToEndOfDay(const Duration(hours: 5, minutes: 12)),
      '5h 12m to EOD',
    );
    expect(formatTimeToEndOfDay(const Duration(minutes: -1)), 'EOD passed');
    expect(event.topMarkets().first.displayLabel, '26°C');
  });

  test('displayChance prefers Buy Yes ask over outcomePrices mid', () {
    final market = OutcomeMarket.fromJson({
      'id': '12',
      'question': '12°C?',
      'groupItemTitle': '12°C',
      'outcomes': '["Yes", "No"]',
      'outcomePrices': '["0.05", "0.95"]',
      'volumeNum': 55,
      'bestAsk': 0.1,
    });
    expect(market.yesPrice, closeTo(0.05, 0.001));
    expect(market.buyYesPrice, closeTo(0.1, 0.001));
    expect(market.displayChance, closeTo(0.1, 0.001));
    expect(formatChancePercent(market.displayChance), '10%');
  });

  test('displayChance uses mid when bid/ask spread is wide', () {
    // Ankara 13°C: Polymarket shows 51% while Buy Yes is 93¢ / Buy No 92¢.
    final market = OutcomeMarket.fromJson({
      'id': '13',
      'question': '13°C or below?',
      'groupItemTitle': '13°C or below',
      'outcomes': '["Yes", "No"]',
      'outcomePrices': '["0.505", "0.495"]',
      'volumeNum': 200,
      'bestBid': 0.08,
      'bestAsk': 0.93,
      'spread': 0.85,
    });
    expect(market.buyYesPrice, closeTo(0.93, 0.001));
    expect(market.displayChance, closeTo(0.505, 0.001));
    expect(formatChancePercent(market.displayChance), '51%');
  });

  test('displayChance is null when one-sided ask conflicts with last trade', () {
    // Ankara 14°C: Polymarket shows "-" for chance while Buy Yes is 92¢.
    final market = OutcomeMarket.fromJson({
      'id': '14',
      'question': '14°C?',
      'groupItemTitle': '14°C',
      'outcomes': '["Yes", "No"]',
      'outcomePrices': '["0.46", "0.54"]',
      'volumeNum': 105,
      'bestAsk': 0.92,
      'lastTradePrice': 0.03,
      'spread': 0.92,
    });
    expect(market.buyYesPrice, closeTo(0.92, 0.001));
    expect(market.displayChance, isNull);
    expect(formatChancePercent(market.displayChance), '—');
  });

  test('displayChance uses lastTrade when Buy Yes ask is unavailable', () {
    final market = OutcomeMarket.fromJson({
      'id': '15',
      'question': '15°C?',
      'groupItemTitle': '15°C',
      'outcomes': '["Yes", "No"]',
      'outcomePrices': '["0.925", "0.075"]',
      'volumeNum': 131,
      'bestBid': 0.85,
      'bestAsk': 1,
      'lastTradePrice': 0.99,
    });
    expect(market.buyYesPrice, isNull);
    expect(market.displayChance, closeTo(0.99, 0.001));
    expect(formatChancePercent(market.displayChance), '99%');
  });

  test('Amsterdam EOD uses city timezone not device local', () {
    final event = MarketEvent.fromJson({
      'id': '2',
      'title': 'Lowest temperature in Amsterdam on September 4?',
      'slug': 'lowest-temperature-in-amsterdam-on-september-4-2026',
      'volume': 100,
      'volume24hr': 50,
      'endDate': '2026-09-04T12:00:00Z',
      'markets': [],
    });

    // Sep 4 23:59:59 in Europe/Amsterdam (CEST, UTC+2) == 21:59:59 UTC.
    final eod = event.localEndOfDay!.toUtc();
    expect(eod.year, 2026);
    expect(eod.month, 9);
    expect(eod.day, 4);
    expect(eod.hour, 21);
    expect(eod.minute, 59);

    // 20:40 Amsterdam (18:40 UTC) → about 3h 19m until EOD.
    final now = DateTime.utc(2026, 9, 4, 18, 40);
    final remaining = eod.difference(now);
    expect(remaining.inHours, 3);
    expect(remaining.inMinutes.remainder(60), 19);
    expect(formatTimeToEndOfDay(remaining), '3h 19m to EOD');
  });
}

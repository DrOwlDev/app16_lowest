import 'dart:convert';
import 'dart:io';

import 'package:app16_lowest/models/market_event.dart';
import 'package:app16_lowest/services/city_timezones.dart';
import 'package:app16_lowest/services/polymarket_api.dart';
import 'package:app16_lowest/services/station_temperature_api.dart';

/// Fetches live Polymarket low-temp markets (+ CLOB asks) and writes
/// `web/data/markets.json` for GitHub Pages.
///
/// Also preloads WRH station temperature series so the web app can render
/// charts without browser calls to weather.gov / Open-Meteo (CORS).
Future<void> main(List<String> args) async {
  CityTimezones.ensureInitialized();

  final outPath = args.isNotEmpty ? args.first : 'web/data/markets.json';
  final api = PolymarketApi(preferStaticSnapshot: false);
  final tempApi = StationTemperatureApi();

  stdout.writeln('Fetching lowest-temperature events…');
  var events = await api.fetchLowestTemperatureEvents();
  stdout.writeln('Enriching CLOB Buy Yes/No for ${events.length} events…');
  events = await api.enrichEventsBuyPrices(events);
  api.close();

  stdout.writeln('Preloading temperature series for WRH stations…');
  events = await _attachTemperatureSeries(events, tempApi);
  tempApi.close();

  final withSeries =
      events.where((e) => e.temperatureSeries != null).length;
  final payload = {
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'eventCount': events.length,
    'temperatureSeriesCount': withSeries,
    'events': events.map((e) => e.toSnapshotJson()).toList(),
  };

  final file = File(outPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  stdout.writeln(
    'Wrote ${events.length} events ($withSeries with temp charts) to $outPath '
    '(${file.lengthSync()} bytes)',
  );
}

Future<List<MarketEvent>> _attachTemperatureSeries(
  List<MarketEvent> events,
  StationTemperatureApi tempApi,
) async {
  final cache = <String, Future<DailyTemperatureSeries?>>{};
  const concurrency = 6;
  var next = 0;
  final results = List<MarketEvent>.from(events);

  Future<DailyTemperatureSeries?> seriesFor(MarketEvent event) {
    final siteId =
        weatherGovTimeseriesSiteId(event.resolutionSourceOpenUrl) ??
            weatherGovTimeseriesSiteId(event.resolutionSourceUrl);
    final day = event.observationDayInCity;
    if (siteId == null || day == null) {
      return Future<DailyTemperatureSeries?>.value(null);
    }

    final unit = event.temperatureUnit ?? 'C';
    final key =
        '${siteId.toUpperCase()}|${day.year}-${day.month}-${day.day}|$unit';
    return cache.putIfAbsent(key, () async {
      try {
        final series = await tempApi.fetchDailySeries(
          siteId: siteId,
          cityName: event.cityName,
          year: day.year,
          month: day.month,
          day: day.day,
          unit: unit,
          observedDataSource:
              event.resolutionSourceUrl ?? event.resolutionSourceOpenUrl,
        );
        stdout.writeln(
          '  ✓ $key (${series.points.length} points, ${event.cityName})',
        );
        return series;
      } catch (e) {
        stdout.writeln('  ✗ $key (${event.cityName}): $e');
        return null;
      }
    });
  }

  Future<void> worker() async {
    while (true) {
      final i = next++;
      if (i >= events.length) return;
      final event = events[i];
      final series = await seriesFor(event);
      if (series != null) {
        results[i] = event.copyWith(temperatureSeries: series);
      }
    }
  }

  await Future.wait([
    for (var w = 0; w < concurrency; w++) worker(),
  ]);
  return results;
}

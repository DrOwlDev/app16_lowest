import 'dart:convert';
import 'dart:io';

import 'package:app16_lowest/services/city_timezones.dart';
import 'package:app16_lowest/services/polymarket_api.dart';

/// Fetches live Polymarket low-temp markets (+ CLOB asks) and writes
/// `web/data/markets.json` for GitHub Pages.
Future<void> main(List<String> args) async {
  CityTimezones.ensureInitialized();

  final outPath = args.isNotEmpty ? args.first : 'web/data/markets.json';
  final api = PolymarketApi(preferStaticSnapshot: false);

  stdout.writeln('Fetching lowest-temperature events…');
  var events = await api.fetchLowestTemperatureEvents();
  stdout.writeln('Enriching CLOB Buy Yes/No for ${events.length} events…');
  events = await api.enrichEventsBuyPrices(events);
  api.close();

  final payload = {
    'updatedAt': DateTime.now().toUtc().toIso8601String(),
    'eventCount': events.length,
    'events': events.map((e) => e.toSnapshotJson()).toList(),
  };

  final file = File(outPath);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
  );
  stdout.writeln(
    'Wrote ${events.length} events to $outPath '
    '(${file.lengthSync()} bytes)',
  );
}

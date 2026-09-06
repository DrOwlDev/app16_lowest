import 'package:app16_lowest/models/market_event.dart';
import 'package:app16_lowest/services/station_temperature_api.dart';
import 'package:timezone/timezone.dart' as tz;

/// How a Polymarket temperature outcome label maps to settlement degrees.
enum TempBucketKind { exact, orBelow, range }

class TempOutcomeBucket {
  const TempOutcomeBucket({
    required this.kind,
    required this.label,
    required this.unit,
    this.exact,
    this.lo,
    this.hi,
  });

  final TempBucketKind kind;
  final String label;
  final String unit; // `C` or `F`
  final double? exact;
  final double? lo;
  final double? hi;

  bool contains(double temp) {
    switch (kind) {
      case TempBucketKind.exact:
        return exact != null && (temp - exact!).abs() < 1e-9;
      case TempBucketKind.orBelow:
        return exact != null && temp <= exact! + 1e-9;
      case TempBucketKind.range:
        if (lo == null || hi == null) return false;
        return temp >= lo! - 1e-9 && temp <= hi! + 1e-9;
    }
  }
}

final _exactRe = RegExp(
  r'^\s*(-?\d+(?:\.\d+)?)\s*°?\s*([CF])\s*$',
  caseSensitive: false,
);
final _orBelowRe = RegExp(
  r'^\s*(-?\d+(?:\.\d+)?)\s*°?\s*([CF])\s+or\s+below\s*$',
  caseSensitive: false,
);
final _rangeRe = RegExp(
  r'^\s*(-?\d+(?:\.\d+)?)\s*-\s*(-?\d+(?:\.\d+)?)\s*°?\s*([CF])\s*$',
  caseSensitive: false,
);

/// Parse outcome labels like `26°C`, `20°C or below`, `50-51°F`.
TempOutcomeBucket? parseTempOutcomeBucket(String label) {
  final raw = label.trim();
  if (raw.isEmpty) return null;

  final orBelow = _orBelowRe.firstMatch(raw);
  if (orBelow != null) {
    final v = double.tryParse(orBelow.group(1)!);
    if (v == null) return null;
    return TempOutcomeBucket(
      kind: TempBucketKind.orBelow,
      label: raw,
      unit: orBelow.group(2)!.toUpperCase(),
      exact: v,
    );
  }

  final range = _rangeRe.firstMatch(raw);
  if (range != null) {
    final a = double.tryParse(range.group(1)!);
    final b = double.tryParse(range.group(2)!);
    if (a == null || b == null) return null;
    final lo = a <= b ? a : b;
    final hi = a <= b ? b : a;
    return TempOutcomeBucket(
      kind: TempBucketKind.range,
      label: raw,
      unit: range.group(3)!.toUpperCase(),
      lo: lo,
      hi: hi,
    );
  }

  final exact = _exactRe.firstMatch(raw);
  if (exact != null) {
    final v = double.tryParse(exact.group(1)!);
    if (v == null) return null;
    return TempOutcomeBucket(
      kind: TempBucketKind.exact,
      label: raw,
      unit: exact.group(2)!.toUpperCase(),
      exact: v,
    );
  }

  return null;
}

/// Min among observed points before [dayEnd]; falls back to daily-min flag.
double? seriesObservedMin(DailyTemperatureSeries series) {
  double? minTemp;
  for (final p in series.points) {
    if (p.kind != TempPointKind.observed) continue;
    if (!p.localHourStart.isBefore(series.dayEnd) &&
        p.localHourStart != series.dayEnd) {
      continue;
    }
    if (p.localHourStart.isAfter(series.dayEnd)) continue;
    if (minTemp == null || p.temperature < minTemp) {
      minTemp = p.temperature;
    }
  }
  if (minTemp != null) return minTemp;
  for (final p in series.points) {
    if (p.isDailyMinimum) return p.temperature;
  }
  return null;
}

/// Min among forecast points at/after [nowLocal] (defaults to series.nowLocal).
double? seriesForecastRemainingMin(
  DailyTemperatureSeries series, {
  tz.TZDateTime? nowLocal,
}) {
  final now = nowLocal ?? series.nowLocal;
  double? minTemp;
  for (final p in series.points) {
    if (p.kind != TempPointKind.forecast) continue;
    if (p.localHourStart.isBefore(now)) continue;
    if (p.localHourStart.isAfter(series.dayEnd)) continue;
    if (minTemp == null || p.temperature < minTemp) {
      minTemp = p.temperature;
    }
  }
  return minTemp;
}

/// Physics-dead: final daily low can only stay or fall from [observedMin].
bool isPhysicsDeadOutcome(TempOutcomeBucket bucket, double observedMin) {
  switch (bucket.kind) {
    case TempBucketKind.exact:
      return bucket.exact != null && observedMin < bucket.exact!;
    case TempBucketKind.range:
      return bucket.lo != null && observedMin < bucket.lo!;
    case TempBucketKind.orBelow:
      return false;
  }
}

bool outcomeMarketIsPhysicsDead(OutcomeMarket market, double observedMin) {
  final bucket = parseTempOutcomeBucket(market.displayLabel);
  if (bucket == null) return false;
  return isPhysicsDeadOutcome(bucket, observedMin);
}

/// Alive bucket that currently contains [observedMin], else colder or-below.
TempOutcomeBucket? leadingSettlementBucket(
  Iterable<OutcomeMarket> markets,
  double observedMin,
) {
  final buckets = <TempOutcomeBucket>[];
  for (final m in markets) {
    final b = parseTempOutcomeBucket(m.displayLabel);
    if (b != null) buckets.add(b);
  }
  if (buckets.isEmpty) return null;

  for (final b in buckets) {
    if (isPhysicsDeadOutcome(b, observedMin)) continue;
    if (b.kind == TempBucketKind.exact && b.contains(observedMin)) return b;
    if (b.kind == TempBucketKind.range && b.contains(observedMin)) return b;
  }

  // Exact integer match when obs is fractional but within the degree (e.g. 17.2 → 17).
  for (final b in buckets) {
    if (b.kind != TempBucketKind.exact || b.exact == null) continue;
    if (isPhysicsDeadOutcome(b, observedMin)) continue;
    if (observedMin >= b.exact! && observedMin < b.exact! + 1) return b;
  }

  TempOutcomeBucket? bestOrBelow;
  for (final b in buckets) {
    if (b.kind != TempBucketKind.orBelow || b.exact == null) continue;
    if (!b.contains(observedMin) && observedMin > b.exact!) continue;
    if (bestOrBelow == null ||
        (b.exact != null &&
            bestOrBelow.exact != null &&
            b.exact! > bestOrBelow.exact!)) {
      bestOrBelow = b;
    }
  }
  return bestOrBelow;
}

String formatTempOneDecimal(double temp) {
  final rounded = (temp * 10).roundToDouble() / 10;
  if ((rounded - rounded.roundToDouble()).abs() < 1e-9) {
    return rounded.round().toString();
  }
  return rounded.toStringAsFixed(1);
}

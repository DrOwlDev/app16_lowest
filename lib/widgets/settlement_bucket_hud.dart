import 'package:flutter/material.dart';

import '../models/market_event.dart';
import '../models/temp_outcome_bucket.dart';
import '../services/station_temperature_api.dart';

/// Compact settlement strip: obs extremum, forecast remaining, leading bucket.
class SettlementBucketHud extends StatelessWidget {
  const SettlementBucketHud({
    super.key,
    required this.series,
    required this.markets,
    required this.tempKind,
  });

  final DailyTemperatureSeries series;
  final List<OutcomeMarket> markets;
  final TempMarketKind tempKind;

  @override
  Widget build(BuildContext context) {
    final high = tempKind == TempMarketKind.high;
    final obs = seriesObservedExtremum(series, tempKind);
    final fcst = seriesForecastRemainingExtremum(series, tempKind);
    final unit = series.unit == 'F' ? 'F' : 'C';
    final leading = obs == null
        ? null
        : leadingSettlementBucket(markets, obs, kind: tempKind);

    String fmt(double? t) =>
        t == null ? '—' : '${formatTempOneDecimal(t)}°$unit';

    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      child: Wrap(
        spacing: 10,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text(
            'Settlement',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF334155),
            ),
          ),
          _kv(high ? 'Obs max' : 'Obs min', fmt(obs)),
          _kv('Fcst rem', fmt(fcst)),
          _kv('Leading', leading?.label ?? '—'),
          if (obs != null)
            Text(
              high ? 'colder buckets dead' : 'warmer buckets dead',
              style: const TextStyle(
                fontSize: 10,
                color: Color(0xFF64748B),
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$k ',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
          TextSpan(
            text: v,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/market_event.dart';
import '../services/polymarket_api.dart';

/// Unique cities with resolution-source URLs from Polymarket Rules.
class MarketsPage extends StatefulWidget {
  const MarketsPage({super.key});

  @override
  State<MarketsPage> createState() => _MarketsPageState();
}

class _CityResolution {
  const _CityResolution({
    required this.cityName,
    required this.resolutionUrl,
    required this.openUrl,
    required this.temperatureUnit,
    required this.eventCount,
    required this.sampleEventUrl,
  });

  final String cityName;
  final String? resolutionUrl;
  final String? openUrl;
  /// `C`, `F`, or null.
  final String? temperatureUnit;
  final int eventCount;
  final String sampleEventUrl;
}

class _MarketsPageState extends State<MarketsPage>
    with AutomaticKeepAliveClientMixin {
  final PolymarketApi _api = PolymarketApi(preferStaticSnapshot: kIsWeb);

  List<_CityResolution> _cities = [];
  bool _loading = true;
  bool _refreshing = false;
  String? _error;
  DateTime? _lastRefreshedAt;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _api.close();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    setState(() {
      if (!silent || _cities.isEmpty) {
        _loading = true;
      } else {
        _refreshing = true;
      }
      _error = null;
    });

    try {
      final events = await _api.fetchLowestTemperatureEvents();
      if (!mounted) return;
      setState(() {
        _cities = _uniqueCities(events);
        _loading = false;
        _refreshing = false;
        _lastRefreshedAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _refreshing = false;
      });
    }
  }

  List<_CityResolution> _uniqueCities(List<MarketEvent> events) {
    final byCity = <String, _CityResolution>{};
    for (final event in events) {
      final city = event.cityName;
      final key = city.toLowerCase();
      final existing = byCity[key];
      final unit = event.temperatureUnit;
      final rawUrl = event.resolutionSourceUrl;
      final openUrl = event.resolutionSourceOpenUrl;
      if (existing == null) {
        byCity[key] = _CityResolution(
          cityName: city,
          resolutionUrl: rawUrl,
          openUrl: openUrl,
          temperatureUnit: unit,
          eventCount: 1,
          sampleEventUrl: event.polymarketUrl,
        );
      } else {
        final mergedUnit = existing.temperatureUnit ?? unit;
        final mergedRaw = existing.resolutionUrl ?? rawUrl;
        byCity[key] = _CityResolution(
          cityName: existing.cityName,
          resolutionUrl: mergedRaw,
          openUrl: mergedRaw == null
              ? null
              : adjustWeatherGovTimeseriesUrl(mergedRaw, mergedUnit),
          temperatureUnit: mergedUnit,
          eventCount: existing.eventCount + 1,
          sampleEventUrl: existing.sampleEventUrl,
        );
      }
    }
    final list = byCity.values.toList()
      ..sort(
        (a, b) => a.cityName.toLowerCase().compareTo(b.cityName.toLowerCase()),
      );
    return list;
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open $url')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _loading && _cities.isEmpty
                      ? 'Cities…'
                      : '${_cities.length} cities (A–Z)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: scheme.primary,
                  ),
                ),
              ),
              if (_refreshing || (_loading && _cities.isNotEmpty))
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_lastRefreshedAt != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    DateFormat.Hm().format(_lastRefreshedAt!),
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              IconButton(
                tooltip: 'Refresh cities',
                visualDensity: VisualDensity.compact,
                onPressed: (_loading || _refreshing) ? null : () => _load(),
                icon: const Icon(Icons.refresh, size: 18),
              ),
            ],
          ),
        ),
        Expanded(child: _buildBody(scheme)),
      ],
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_loading && _cities.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _cities.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: () => _load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_cities.isEmpty) {
      return const Center(child: Text('No cities found'));
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      itemCount: _cities.length,
      separatorBuilder: (_, _) => const SizedBox(height: 4),
      itemBuilder: (context, index) {
        final row = _cities[index];
        final displayUrl = row.openUrl ?? row.resolutionUrl;
        final siteId = weatherGovTimeseriesSiteId(row.resolutionUrl);
        final isStandardTimeseries = siteId != null;
        final titleText = isStandardTimeseries
            ? '${row.cityName} - $siteId'
            : row.cityName;
        return Card(
          child: ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 2,
            ),
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    titleText,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (row.temperatureUnit != null) ...[
                  const SizedBox(width: 6),
                  _UnitBadge(unit: row.temperatureUnit!),
                ],
                if (!isStandardTimeseries) ...[
                  const SizedBox(width: 6),
                  const _UniqueSourceBadge(),
                ],
              ],
            ),
            subtitle: displayUrl == null
                ? Text(
                    'No resolution source URL · ${row.eventCount} market(s)',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  )
                : Text(
                    displayUrl,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.primary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (displayUrl != null)
                  IconButton(
                    tooltip: 'Open resolution source',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openUrl(displayUrl),
                    icon: Icon(
                      Icons.cloud_outlined,
                      size: 18,
                      color: scheme.primary,
                    ),
                  ),
                IconButton(
                  tooltip: 'Open on Polymarket',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _openUrl(row.sampleEventUrl),
                  icon: Icon(
                    Icons.open_in_new,
                    size: 16,
                    color: scheme.primary,
                  ),
                ),
              ],
            ),
            onTap: displayUrl != null
                ? () => _openUrl(displayUrl)
                : () => _openUrl(row.sampleEventUrl),
          ),
        );
      },
    );
  }
}

class _UnitBadge extends StatelessWidget {
  const _UnitBadge({required this.unit});

  final String unit;

  @override
  Widget build(BuildContext context) {
    final isC = unit == 'C';
    final color = isC ? const Color(0xFF0D9488) : const Color(0xFFEA580C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Text(
        isC ? '°C' : '°F',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _UniqueSourceBadge extends StatelessWidget {
  const _UniqueSourceBadge();

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.55)),
      ),
      child: const Text(
        'Unique Resolution Source',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

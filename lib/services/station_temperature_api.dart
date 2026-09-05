import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:timezone/timezone.dart' as tz;

import 'city_timezones.dart';

enum TempPointKind { observed, forecast }

class HourlyTempPoint {
  const HourlyTempPoint({
    required this.localHourStart,
    required this.temperature,
    required this.kind,
    this.dataSource = '',
    this.isDailyMinimum = false,
    this.isDailyMaximum = false,
  });

  /// City-local timestamp for this sample (may be sub-hourly for observations).
  final tz.TZDateTime localHourStart;
  final double temperature;
  final TempPointKind kind;

  /// Where the value came from (WRH URL, api.weather.gov, api.open-meteo.com, …).
  final String dataSource;

  /// True when this hour ties the observation-day minimum temperature.
  final bool isDailyMinimum;

  /// True when this hour ties the observation-day maximum temperature.
  final bool isDailyMaximum;

  HourlyTempPoint copyWith({
    String? dataSource,
    bool? isDailyMinimum,
    bool? isDailyMaximum,
  }) {
    return HourlyTempPoint(
      localHourStart: localHourStart,
      temperature: temperature,
      kind: kind,
      dataSource: dataSource ?? this.dataSource,
      isDailyMinimum: isDailyMinimum ?? this.isDailyMinimum,
      isDailyMaximum: isDailyMaximum ?? this.isDailyMaximum,
    );
  }
}

class DailyTemperatureSeries {
  const DailyTemperatureSeries({
    required this.siteId,
    required this.unit,
    required this.dayStart,
    required this.dayEnd,
    required this.nowLocal,
    required this.points,
  });

  final String siteId;
  /// `C` or `F`.
  final String unit;
  final tz.TZDateTime dayStart;
  final tz.TZDateTime dayEnd;
  final tz.TZDateTime nowLocal;
  final List<HourlyTempPoint> points;
}

/// Fetches observed METARs + hourly forecast for a WRH timeseries site day.
class StationTemperatureApi {
  StationTemperatureApi({http.Client? client})
      : _client = client ?? http.Client();

  static const _aviationBase = 'https://aviationweather.gov/api/data';
  static const _nwsBase = 'https://api.weather.gov';
  static const _openMeteoBase = 'https://api.open-meteo.com/v1/forecast';
  static const _userAgent =
      'app16_lowest (https://github.com/DrOwlDev/app16_lowest)';

  /// Default observed label when the market resolution URL is unavailable.
  static const defaultObservedDataSource =
      'https://www.weather.gov/wrh/timeseries';
  static const nwsForecastDataSource = 'api.weather.gov';
  static const openMeteoForecastDataSource = 'api.open-meteo.com';

  final http.Client _client;

  Future<DailyTemperatureSeries> fetchDailySeries({
    required String siteId,
    required String cityName,
    required int year,
    required int month,
    required int day,
    required String unit,
    String? observedDataSource,
    DateTime? nowUtc,
  }) async {
    final location = CityTimezones.locationForCity(cityName) ?? tz.UTC;
    final dayStart = tz.TZDateTime(location, year, month, day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    final nowLocal = tz.TZDateTime.from(
      (nowUtc ?? DateTime.now()).toUtc(),
      location,
    );

    final icao = siteId.toUpperCase();
    final station = await _fetchStation(icao);
    final hoursNeeded = math.max(
      24,
      dayEnd.toUtc().difference(DateTime.now().toUtc()).inHours.abs() + 36,
    );

    final obsC = await _fetchMetarObservationsC(
      icao: icao,
      location: location,
      dayStart: dayStart,
      dayEnd: dayEnd,
      hours: hoursNeeded.clamp(24, 72),
    );

    var forecastC = <int, double>{};
    var forecastSource = openMeteoForecastDataSource;
    if (station != null) {
      final forecast = await _fetchForecastHourlyC(
        lat: station.lat,
        lon: station.lon,
        location: location,
        dayStart: dayStart,
        dayEnd: dayEnd,
      );
      forecastC = forecast.temps;
      forecastSource = forecast.source;
    }

    final obsSource = (observedDataSource != null &&
            observedDataSource.trim().isNotEmpty)
        ? observedDataSource.trim()
        : defaultObservedDataSource;

    final points = mergeHourlySeries(
      dayStart: dayStart,
      dayEnd: dayEnd,
      nowLocal: nowLocal,
      observedC: obsC,
      forecastC: forecastC,
      unit: unit == 'F' ? 'F' : 'C',
      observedDataSource: obsSource,
      forecastDataSource: forecastSource,
    );

    return DailyTemperatureSeries(
      siteId: icao,
      unit: unit == 'F' ? 'F' : 'C',
      dayStart: dayStart,
      dayEnd: dayEnd,
      nowLocal: nowLocal,
      points: points,
    );
  }

  Future<({double lat, double lon})?> _fetchStation(String icao) async {
    final uri = Uri.parse(
      '$_aviationBase/stationinfo?ids=$icao&format=json',
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! List || decoded.isEmpty) return null;
    final first = decoded.first;
    if (first is! Map) return null;
    final lat = (first['lat'] as num?)?.toDouble();
    final lon = (first['lon'] as num?)?.toDouble();
    if (lat == null || lon == null) return null;
    return (lat: lat, lon: lon);
  }

  Future<Map<int, double>> _fetchMetarObservationsC({
    required String icao,
    required tz.Location location,
    required tz.TZDateTime dayStart,
    required tz.TZDateTime dayEnd,
    required int hours,
  }) async {
    final uri = Uri.parse(
      '$_aviationBase/metar?ids=$icao&format=json&hours=$hours',
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) return {};
    final decoded = jsonDecode(response.body);
    if (decoded is! List) return {};

    final samples = <({DateTime utc, double tempC})>[];
    for (final item in decoded) {
      if (item is! Map) continue;
      final temp = (item['temp'] as num?)?.toDouble();
      if (temp == null) continue;
      final reportTime = DateTime.tryParse(item['reportTime']?.toString() ?? '');
      DateTime? obsUtc;
      if (reportTime != null) {
        obsUtc = reportTime.toUtc();
      } else {
        final obsSec = item['obsTime'];
        if (obsSec is num) {
          obsUtc = DateTime.fromMillisecondsSinceEpoch(
            (obsSec * 1000).round(),
            isUtc: true,
          );
        }
      }
      if (obsUtc == null) continue;
      samples.add((utc: obsUtc, tempC: temp));
    }
    return indexMetarObservations(
      location: location,
      dayStart: dayStart,
      dayEnd: dayEnd,
      samples: samples,
    );
  }

  Future<({Map<int, double> temps, String source})> _fetchForecastHourlyC({
    required double lat,
    required double lon,
    required tz.Location location,
    required tz.TZDateTime dayStart,
    required tz.TZDateTime dayEnd,
  }) async {
    final nws = await _fetchNwsHourlyC(
      lat: lat,
      lon: lon,
      location: location,
      dayStart: dayStart,
      dayEnd: dayEnd,
    );
    if (nws.isNotEmpty) {
      return (temps: nws, source: nwsForecastDataSource);
    }
    final om = await _fetchOpenMeteoHourlyC(
      lat: lat,
      lon: lon,
      location: location,
      dayStart: dayStart,
      dayEnd: dayEnd,
    );
    return (temps: om, source: openMeteoForecastDataSource);
  }

  Future<Map<int, double>> _fetchNwsHourlyC({
    required double lat,
    required double lon,
    required tz.Location location,
    required tz.TZDateTime dayStart,
    required tz.TZDateTime dayEnd,
  }) async {
    try {
      final pointsUri = Uri.parse(
        '$_nwsBase/points/${lat.toStringAsFixed(4)},${lon.toStringAsFixed(4)}',
      );
      final pointsRes = await _client.get(
        pointsUri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/geo+json',
        },
      );
      if (pointsRes.statusCode != 200) return {};
      final pointsJson = jsonDecode(pointsRes.body);
      final pointsProps =
          pointsJson is Map ? pointsJson['properties'] : null;
      final hourlyUrl =
          pointsProps is Map ? pointsProps['forecastHourly'] : null;
      if (hourlyUrl is! String || hourlyUrl.isEmpty) return {};

      final hourlyRes = await _client.get(
        Uri.parse(hourlyUrl),
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/geo+json',
        },
      );
      if (hourlyRes.statusCode != 200) return {};
      final hourlyJson = jsonDecode(hourlyRes.body);
      final hourlyProps =
          hourlyJson is Map ? hourlyJson['properties'] : null;
      final periods = hourlyProps is Map ? hourlyProps['periods'] : null;
      if (periods is! List) return {};

      final out = <int, double>{};
      for (final p in periods) {
        if (p is! Map) continue;
        final start = DateTime.tryParse(p['startTime']?.toString() ?? '');
        final temp = (p['temperature'] as num?)?.toDouble();
        final unit = p['temperatureUnit']?.toString().toUpperCase();
        if (start == null || temp == null) continue;
        final local = tz.TZDateTime.from(start.toUtc(), location);
        final hourStart = tz.TZDateTime(
          location,
          local.year,
          local.month,
          local.day,
          local.hour,
        );
        // Include next-day local 00:00 (dayEnd) as the series endpoint.
        if (hourStart.isBefore(dayStart) || hourStart.isAfter(dayEnd)) continue;
        final tempC = unit == 'F' ? fahrenheitToCelsius(temp) : temp;
        out[hourStart.millisecondsSinceEpoch] = tempC;
      }
      return out;
    } catch (_) {
      return {};
    }
  }

  Future<Map<int, double>> _fetchOpenMeteoHourlyC({
    required double lat,
    required double lon,
    required tz.Location location,
    required tz.TZDateTime dayStart,
    required tz.TZDateTime dayEnd,
  }) async {
    final uri = Uri.parse(_openMeteoBase).replace(
      queryParameters: {
        'latitude': lat.toString(),
        'longitude': lon.toString(),
        'hourly': 'temperature_2m',
        'forecast_days': '2',
        'past_days': '1',
        'timezone': 'auto',
      },
    );
    final response = await _client.get(uri);
    if (response.statusCode != 200) return {};
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return {};
    final hourly = decoded['hourly'];
    if (hourly is! Map) return {};
    final times = hourly['time'];
    final temps = hourly['temperature_2m'];
    if (times is! List || temps is! List) return {};

    final out = <int, double>{};
    for (var i = 0; i < times.length && i < temps.length; i++) {
      final t = DateTime.tryParse(times[i].toString());
      final temp = (temps[i] as num?)?.toDouble();
      if (t == null || temp == null) continue;
      // Open-Meteo returns local wall times when timezone=auto (no Z).
      final local = t.isUtc
          ? tz.TZDateTime.from(t, location)
          : tz.TZDateTime(
              location,
              t.year,
              t.month,
              t.day,
              t.hour,
              t.minute,
            );
      final hourStart = tz.TZDateTime(
        location,
        local.year,
        local.month,
        local.day,
        local.hour,
      );
      // Include next-day local 00:00 (dayEnd) as the series endpoint.
      if (hourStart.isBefore(dayStart) || hourStart.isAfter(dayEnd)) continue;
      out[hourStart.millisecondsSinceEpoch] = temp;
    }
    return out;
  }

  void close() => _client.close();
}

/// Index METAR samples at native local resolution (minute precision).
///
/// Stations that report every 30 minutes (e.g. VILK) keep both :00 and :30
/// points instead of collapsing to one value per hour. Later samples win on
/// the same local minute.
Map<int, double> indexMetarObservations({
  required tz.Location location,
  required tz.TZDateTime dayStart,
  required tz.TZDateTime dayEnd,
  required List<({DateTime utc, double tempC})> samples,
}) {
  final sorted = [...samples]
    ..sort((a, b) => a.utc.toUtc().compareTo(b.utc.toUtc()));
  final out = <int, double>{};
  for (final sample in sorted) {
    final local = tz.TZDateTime.from(sample.utc.toUtc(), location);
    final atMinute = tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day,
      local.hour,
      local.minute,
    );
    if (atMinute.isBefore(dayStart) || atMinute.isAfter(dayEnd)) continue;
    out[atMinute.millisecondsSinceEpoch] = sample.tempC;
  }
  return out;
}

double celsiusToFahrenheit(double c) => c * 9 / 5 + 32;

double fahrenheitToCelsius(double f) => (f - 32) * 5 / 9;

double convertTempC(double tempC, String unit) =>
    unit == 'F' ? celsiusToFahrenheit(tempC) : tempC;

/// Merge native-resolution observations with hourly forecasts.
///
/// Observed points keep their native timestamps (e.g. every 30 min). Forecast
/// points stay on the hour for times after [nowLocal] (and the current hour
/// when no observation exists in that hour). Includes next-day local 00:00.
List<HourlyTempPoint> mergeHourlySeries({
  required tz.TZDateTime dayStart,
  required tz.TZDateTime dayEnd,
  required tz.TZDateTime nowLocal,
  required Map<int, double> observedC,
  required Map<int, double> forecastC,
  required String unit,
  String observedDataSource =
      StationTemperatureApi.defaultObservedDataSource,
  String forecastDataSource =
      StationTemperatureApi.openMeteoForecastDataSource,
}) {
  final location = dayStart.location;
  final points = <HourlyTempPoint>[];

  bool hasObsInHour(tz.TZDateTime hourStart) {
    final hourEnd = hourStart.add(const Duration(hours: 1));
    for (final key in observedC.keys) {
      final t = tz.TZDateTime.fromMillisecondsSinceEpoch(location, key);
      if (!t.isBefore(hourStart) && t.isBefore(hourEnd)) return true;
    }
    return false;
  }

  final obsKeys = observedC.keys.toList()..sort();
  for (final key in obsKeys) {
    final t = tz.TZDateTime.fromMillisecondsSinceEpoch(location, key);
    if (t.isBefore(dayStart) || t.isAfter(dayEnd)) continue;
    if (t.isAfter(nowLocal)) continue;
    points.add(
      HourlyTempPoint(
        localHourStart: t,
        temperature: convertTempC(observedC[key]!, unit),
        kind: TempPointKind.observed,
        dataSource: observedDataSource,
      ),
    );
  }

  var hour = dayStart;
  while (!hour.isAfter(dayEnd)) {
    final key = hour.millisecondsSinceEpoch;
    final fc = forecastC[key];
    final hourEnd = hour.add(const Duration(hours: 1));
    if (fc != null) {
      final containsNow =
          !nowLocal.isBefore(hour) && nowLocal.isBefore(hourEnd);
      final fullyFuture = !hour.isBefore(nowLocal);
      if (fullyFuture || (containsNow && !hasObsInHour(hour))) {
        // Avoid duplicating a forecast at the same instant as an observation.
        final alreadyObs = observedC.containsKey(key) &&
            !tz.TZDateTime.fromMillisecondsSinceEpoch(location, key)
                .isAfter(nowLocal);
        if (!alreadyObs) {
          points.add(
            HourlyTempPoint(
              localHourStart: hour,
              temperature: convertTempC(fc, unit),
              kind: TempPointKind.forecast,
              dataSource: forecastDataSource,
            ),
          );
        }
      }
    }
    hour = hourEnd;
  }

  points.sort(
    (a, b) => a.localHourStart.millisecondsSinceEpoch
        .compareTo(b.localHourStart.millisecondsSinceEpoch),
  );
  return markDailyExtremes(points, dayEnd);
}

/// Marks observation-day samples that tie the day's min/max temperature.
///
/// Next-day local midnight ([dayEnd]) is excluded from the extreme set.
List<HourlyTempPoint> markDailyExtremes(
  List<HourlyTempPoint> points,
  tz.TZDateTime dayEnd,
) {
  final dayPoints =
      points.where((p) => p.localHourStart.isBefore(dayEnd)).toList();
  if (dayPoints.isEmpty) return points;
  final minTemp =
      dayPoints.map((p) => p.temperature).reduce((a, b) => a < b ? a : b);
  final maxTemp =
      dayPoints.map((p) => p.temperature).reduce((a, b) => a > b ? a : b);
  return [
    for (final p in points)
      p.copyWith(
        isDailyMinimum: p.localHourStart.isBefore(dayEnd) &&
            (p.temperature - minTemp).abs() < 1e-9,
        isDailyMaximum: p.localHourStart.isBefore(dayEnd) &&
            (p.temperature - maxTemp).abs() < 1e-9,
      ),
  ];
}

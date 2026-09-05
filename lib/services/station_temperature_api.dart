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
    this.isDailyMinimum = false,
  });

  /// City-local hour start (timezone-aware).
  final tz.TZDateTime localHourStart;
  final double temperature;
  final TempPointKind kind;

  /// True when this hour ties the observation-day minimum temperature.
  final bool isDailyMinimum;

  HourlyTempPoint copyWith({bool? isDailyMinimum}) {
    return HourlyTempPoint(
      localHourStart: localHourStart,
      temperature: temperature,
      kind: kind,
      isDailyMinimum: isDailyMinimum ?? this.isDailyMinimum,
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

  final http.Client _client;

  Future<DailyTemperatureSeries> fetchDailySeries({
    required String siteId,
    required String cityName,
    required int year,
    required int month,
    required int day,
    required String unit,
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

    final obsC = await _fetchMetarHourlyC(
      icao: icao,
      location: location,
      dayStart: dayStart,
      dayEnd: dayEnd,
      hours: hoursNeeded.clamp(24, 72),
    );

    Map<int, double> forecastC = {};
    if (station != null) {
      forecastC = await _fetchForecastHourlyC(
        lat: station.lat,
        lon: station.lon,
        location: location,
        dayStart: dayStart,
        dayEnd: dayEnd,
      );
    }

    final points = mergeHourlySeries(
      dayStart: dayStart,
      dayEnd: dayEnd,
      nowLocal: nowLocal,
      observedC: obsC,
      forecastC: forecastC,
      unit: unit == 'F' ? 'F' : 'C',
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

  Future<Map<int, double>> _fetchMetarHourlyC({
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
    return bucketMetarObservations(
      location: location,
      dayStart: dayStart,
      dayEnd: dayEnd,
      samples: samples,
    );
  }

  Future<Map<int, double>> _fetchForecastHourlyC({
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
    if (nws.isNotEmpty) return nws;
    return _fetchOpenMeteoHourlyC(
      lat: lat,
      lon: lon,
      location: location,
      dayStart: dayStart,
      dayEnd: dayEnd,
    );
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

class _ObsCandidate {
  const _ObsCandidate({required this.tempC, required this.score});
  final double tempC;
  final int score;
}

/// Prefer METARs near top-of-hour (:50–:59), then close to :00.
int metarHourScore(int minute) {
  if (minute >= 50) return 100 + minute;
  if (minute <= 10) return 80 - minute;
  return 40 - (minute - 30).abs();
}

/// Bucket METAR samples into city-local hours (best score wins).
Map<int, double> bucketMetarObservations({
  required tz.Location location,
  required tz.TZDateTime dayStart,
  required tz.TZDateTime dayEnd,
  required List<({DateTime utc, double tempC})> samples,
}) {
  final candidates = <int, _ObsCandidate>{};
  for (final sample in samples) {
    final local = tz.TZDateTime.from(sample.utc.toUtc(), location);
    final hourStart = tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day,
      local.hour,
    );
    // Include next-day local 00:00 (dayEnd) as the series endpoint.
    if (hourStart.isBefore(dayStart) || hourStart.isAfter(dayEnd)) continue;
    final key = hourStart.millisecondsSinceEpoch;
    final score = metarHourScore(local.minute);
    final existing = candidates[key];
    if (existing == null || score > existing.score) {
      candidates[key] = _ObsCandidate(tempC: sample.tempC, score: score);
    }
  }
  return {for (final e in candidates.entries) e.key: e.value.tempC};
}

double celsiusToFahrenheit(double c) => c * 9 / 5 + 32;

double fahrenheitToCelsius(double f) => (f - 32) * 5 / 9;

double convertTempC(double tempC, String unit) =>
    unit == 'F' ? celsiusToFahrenheit(tempC) : tempC;

/// Pure merge used by API and unit tests.
///
/// Includes hours `[dayStart, dayEnd]` so next-day local 00:00 is plotted.
List<HourlyTempPoint> mergeHourlySeries({
  required tz.TZDateTime dayStart,
  required tz.TZDateTime dayEnd,
  required tz.TZDateTime nowLocal,
  required Map<int, double> observedC,
  required Map<int, double> forecastC,
  required String unit,
}) {
  final points = <HourlyTempPoint>[];
  var hour = dayStart;
  // Inclusive of dayEnd (next local midnight).
  while (!hour.isAfter(dayEnd)) {
    final key = hour.millisecondsSinceEpoch;
    final hourEnd = hour.add(const Duration(hours: 1));
    final obs = observedC[key];
    final fc = forecastC[key];

    double? tempC;
    TempPointKind? kind;

    if (!hourEnd.isAfter(nowLocal)) {
      // Fully in the past → observed only.
      if (obs != null) {
        tempC = obs;
        kind = TempPointKind.observed;
      }
    } else if (!hour.isBefore(nowLocal)) {
      // Fully in the future → forecast only.
      if (fc != null) {
        tempC = fc;
        kind = TempPointKind.forecast;
      }
    } else {
      // Hour contains now → prefer observed.
      if (obs != null) {
        tempC = obs;
        kind = TempPointKind.observed;
      } else if (fc != null) {
        tempC = fc;
        kind = TempPointKind.forecast;
      }
    }

    if (tempC != null && kind != null) {
      points.add(
        HourlyTempPoint(
          localHourStart: hour,
          temperature: convertTempC(tempC, unit),
          kind: kind,
        ),
      );
    }
    hour = hourEnd;
  }
  return markDailyMinima(points, dayEnd);
}

/// Marks observation-day hours that tie the day's minimum temperature.
///
/// Next-day local midnight ([dayEnd]) is excluded from the minimum set.
List<HourlyTempPoint> markDailyMinima(
  List<HourlyTempPoint> points,
  tz.TZDateTime dayEnd,
) {
  final dayPoints =
      points.where((p) => p.localHourStart.isBefore(dayEnd)).toList();
  if (dayPoints.isEmpty) return points;
  final minTemp =
      dayPoints.map((p) => p.temperature).reduce((a, b) => a < b ? a : b);
  return [
    for (final p in points)
      p.copyWith(
        isDailyMinimum: p.localHourStart.isBefore(dayEnd) &&
            (p.temperature - minTemp).abs() < 1e-9,
      ),
  ];
}

# app16_lowest

Flutter **Windows + Android + web** app for browsing Polymarket
[lowest](https://polymarket.com/weather/low-temperature) and
[highest](https://polymarket.com/weather/high-temperature) temperature weather markets,
with expand charts aligned to each market’s **resolution source**.

| Platform | Data |
|---|---|
| **Windows / Android** | Live Polymarket Gamma + CLOB; live weather APIs for charts |
| **GitHub Pages** | Same-origin `data/markets.json` (odds + preloaded temp series; no browser CORS) |

- Live site: https://drowldev.github.io/app16_lowest/
- Android package id: `dev.drowl.app16` (release APK/AAB signed from local `android/key.properties` + keystore; not committed)
- Proxy wallet for **Current Positions**: `0x8cEF3c1B592953D61EEE2bC9375C5944A8926B6d`
- Gamma tags: Lowest `104597` + Highest `104596` (unified list, deduped by event id)

---

## Run

```bash
flutter pub get
flutter run -d windows
flutter run -d android
```

Release Android (requires signing files under `android/`):

```bash
flutter build apk --release
flutter build appbundle --release
```

Web snapshot + build:

```bash
dart run tool/export_markets.dart web/data/markets.json
flutter build web --release --base-href /app16_lowest/
```

- Deploy: Flutter web on every `main` push ([Deploy GitHub Pages](https://github.com/DrOwlDev/app16_lowest/actions/workflows/deploy-pages.yml))
- Data refresh workflow: updates `gh-pages` `data/markets.json` about every **5 minutes**
  ([Refresh Pages Data](https://github.com/DrOwlDev/app16_lowest/actions/workflows/refresh-data.yml))

---

## Tabs

1. **Temperature Markets** — unified browser of low + high daily temperature markets
2. **Sites** — unique cities A–Z with resolution URLs
3. **Current Positions** — open positions for the configured Polymarket proxy wallet

UI defaults: white scaffold/cards; dense layout (no wasteful top banners). Each market row shows a **Low** / **High** chip.

---

## Temperature Markets logic

### Listing & refresh

- Hide markets past **local EOD** (always; no toggle). EOD = **23:59 in the market city’s timezone**, not Polymarket close/resolution time.
- Sort by **time-to-EOD** (soonest first). EOD badge shows duration only (`Xh Ym`): red &lt;1h, orange &lt;3h, else blue.
- Show **all active market dates** (no date filter).
- **Auto-refresh every 3 minutes** (silent; preserves search, strategy, type filter, expanded row). Manual Refresh does the same. EOD countdown UI ticks every 30s.
- Only **one** accordion open at a time. Expanding a row reloads that market’s Buy Yes/No; per-row refresh control available.

### Type filter (default: Low & High)

| Type | Rule |
|---|---|
| Low | Only Lowest temperature markets |
| High | Only Highest temperature markets |
| Low & High | All temperature markets |

### Strategy filter (default: locked-with-Nos)

| Strategy | Rule |
|---|---|
| Show All | No strategy filter |
| Find Locked Market (≥ 90%) with No's Opportunities | ≥1 outcome with chance ≥ 90%, **and** another with chance &lt; 90% where Buy No &gt; 1¢ and not `--` |
| Find Markets with only 1 Buy Yes &gt;95c | **Exactly one** temperature with Buy Yes ≥ 95¢ |

### Other filters (on by default)

- **Hide thin rows**: hide outcomes where Buy Yes &lt; 1¢ **and** Buy No is `--` (not volume / chance filters).
- **Hide non-Min/Max table rows**: temperature **table** only — keep Extreme Min/Max + all Forecasted rows; chart points unchanged.
- **Search city**: title / city substring.

### Odds / chance (match Polymarket site)

- **Buy Yes / Buy No**: CLOB asks (show `--` when unavailable).
- **Chance %** (large Polymarket-style %):
  - Wide bid–ask (≥ 15¢): prefer **last trade**, else **mid** (`outcomePrices`) — not the Yes ask.
  - Tight book: Yes ask.
  - Conflicting one-sided ask vs last (≥ 15¢ apart): treat as unavailable (`—`).
- Top chips format: `x% @ yC` (no redundant separate “% Yes” label).
- Row / chip / temp-row colors: ≥95% green, ≥90% yellow, ≥80% cyan, else white.
- Date badges vary by calendar day but never red/green/yellow/blue.

### Expand temperature chart

Shown when the market is **chartable** (see [Resolution sources](#resolution-sources--charts) below).

- City-local day: **00:00 → next-day 00:00** inclusive.
- **Observed** before now (black, native station timing); **forecast** after (yellow).
- Blue min / orange max lines + stars (full decimal precision from series).
- Red **now** line; label uses latest station obs temp/time when available.
- Table: Extreme column next to Temp; optional Min/Max row filter above.
- **Settlement HUD** (when series loaded): for **Low** — Obs min / Fcst rem (min) / Leading / warmer buckets dead; for **High** — Obs max / Fcst rem (max) / Leading / colder buckets dead. Physics-dead outcomes get a **Dead** chip (low: final min can only fall; high: final max can only rise). Obs min/max/Dead use **real observed points only** (never forecast extrema).
- **In-app alerts** (SnackBar + dismissible strip): new lower obs min (low markets) or higher obs max (high markets) on expanded charts; newly appearing lock-with-No after refresh.

### Current Positions

- Joins to Temperature Markets cache by `eventSlug`/`slug` and CLOB `asset` → token ids.
- Chips: outcome label, live **chance** (`displayChance`, else Data API mark), city-local **EOD**.
- Tap row → Temperature Markets tab and expand that event; external Polymarket icon still available.
- Auto-refresh every 3 minutes.

---

## Resolution sources & charts

Routing (Windows/Android live / export preload):

```
Hong Kong (HKO)     → HkoTemperatureApi
WRH timeseries      → StationTemperatureApi (ICAO/site from ?site=)
WU airport history  → StationTemperatureApi (ICAO from URL path)
```

| Kind | Detection | Observed | Forecast | Sites title | Unique badge |
|---|---|---|---|---|---|
| **NOAA WRH** | `weather.gov/wrh/timeseries?site=` | aviationweather.gov METAR | NWS hourly → Open-Meteo NBM (`ncep_nbm_conus`) → default Open-Meteo | `City - siteId` | No |
| **Weather Underground airport** | `wunderground.com/history/daily/.../{ICAO}` (e.g. Jinan **ZSJN**, Taipei **RCSS**) | METAR for ICAO; if AWC empty (e.g. ZSJN) → Weather.com historical (same feed as WU Daily Observations) | Open-Meteo at airport lat/lon (NWS/NBM don’t cover CN/TW) | `City - ICAO` | **Yes** (keep) |
| **Hong Kong HKO** | `weather.gov.hk` / `hko.gov.hk` or city name Hong Kong | `hkoc.csv` (minute, HKT) | OCF `HKO.xml`; now-label from latest 1-min CSV | city name | **Yes** |

Notes:

- °C WRH open URLs append `&units=metric`; °F left unchanged.
- HKO settlement reference remains Daily Extract Absolute temps (not scraped for the live curve).
- WU markets settle on **whole °C** from the Daily Observations table (not Day High & Low summary). Do not use city AWS (CWA/CMA) or WU BestForecast as primary observed/forecast.
- Pages export (`tool/export_markets.dart`) preloads WRH + WU-ICAO + HKO series into the snapshot so web charts work offline of weather APIs.

---

## Sites tab

- Unique cities A–Z from market resolution URLs (Gamma `resolutionSource` or Rules/description).
- °C / °F badges from outcome labels.
- Search matches city name, WRH site id, or WU ICAO.
- Non-WRH sources show red **Unique Resolution Source** badge (including WU and HKO).

---

## Key files

| Path | Role |
|---|---|
| `lib/main.dart` | Temperature Markets UI, Type/Strategy filters, alerts, 3‑min refresh, expand + chart routing |
| `lib/services/polymarket_api.dart` | Gamma dual-tag fetch (104597 + 104596) + CLOB enrich; live on Windows/Android, static snapshot on web |
| `lib/models/temp_outcome_bucket.dart` | Settlement bucket parse + kind-aware physics-dead outcomes |
| `lib/models/market_event.dart` | Odds/chance, strategies, EOD, chart eligibility (WRH / WU / HKO) |
| `lib/services/station_temperature_api.dart` | METAR + forecast cascade + Weather.com historical fallback |
| `lib/services/hko_temperature_api.dart` | Hong Kong observed + OCF |
| `lib/pages/markets_page.dart` | Sites directory |
| `lib/pages/positions_page.dart` | Positions + live odds/EOD + deep-link |
| `lib/widgets/settlement_bucket_hud.dart` | Settlement HUD strip |
| `tool/export_markets.dart` | Pages snapshot exporter |
| `.github/workflows/deploy-pages.yml` | Web build + gh-pages deploy on `main` |
| `.github/workflows/refresh-data.yml` | ~5‑min snapshot refresh |

---

## Tests

```bash
flutter test
```

Coverage includes chance/strategy/EOD parsing, WRH METAR merge, HKO parsers, and WU ICAO + Weather.com historical fallback (Jinan/Taipei isolation from HKO/WRH).

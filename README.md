# app16_lowest

Flutter app for browsing Polymarket **lowest-temperature** weather markets.

## Windows (live APIs)

```bash
flutter pub get
flutter run -d windows
```

Uses Polymarket Gamma + CLOB directly.

## GitHub Pages (static snapshot)

Web build reads `data/markets.json` (same-origin) so browser CORS is not required.
That snapshot includes Polymarket odds **and** preloaded WRH station temperature
series (METAR + NWS/Open-Meteo) so expand charts work without live weather APIs.

- Site: https://drowldev.github.io/app16_lowest/
- Deploy workflow: builds Flutter web on every `main` push
- Refresh workflow: updates `data/markets.json` on `gh-pages` about every 5 minutes

```bash
dart run tool/export_markets.dart web/data/markets.json
flutter build web --release --base-href /app16_lowest/
```

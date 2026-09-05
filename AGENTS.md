## Learned User Preferences

- Prefer a dense Windows UI: tighter spacing, smaller market heading fonts, and no top banners (e.g. remove "Low Temp Markets") that waste vertical space.
- Avoid redundant labels; if a degree already shows its percentage (e.g. "14° 99%"), do not also show a separate "% Yes" style label; format top outcomes as "x% @ yC" (e.g. "70% @ 26C").
- Always hide markets past local EOD (no toggle), sort by time-to-EOD, always auto-refresh every 1 minute (no checkbox), and show all active market dates (no date filter).
- Use sliders for Min convergence (1% steps) and Min time-to-EOD (15 min steps; default ≥ 0 min showing everything), not multi-select buttons.
- Outcome percentages and Buy Yes / Buy No must match Polymarket’s live display (including "-" / unavailable when Polymarket shows no odds); chance % is Polymarket’s large percentage—on wide bid-ask prefer mid over a stale last trade when Polymarket shows mid (e.g. 29% vs last 68%), not Buy Yes ask.
- Accordion expand: only one market open at a time; no blue city badge; when expanded, show Buy Yes and Buy No; refresh that market’s odds on expand (and via a per-market refresh control).
- Color rules: date badges vary by calendar day but never red/green/yellow/blue; EOD badge shows duration only (no "to EOD" suffix)—red if <1h, orange if <3h, else blue; market row / top-outcome chip / temperature rows use ≥95% green, ≥90% yellow, ≥80% cyan, else white.
- Strategy dropdown: "Show All" vs "Find Locked Market (≥ 90%) with No's Opportunities" (at least one temperature with chance ≥ 90%, and at least one other with chance < 90% where Buy No > 1¢ and not "--"); default to the locked-with-Nos strategy on startup.
- "Hide thin rows" on by default: hide outcomes only when Buy Yes < 1¢ and Buy No is "--" (do not filter by volume or chance <1%).
- Multi-tab UI: "Low Markets" (market browser), "Sites" (city directory), and "Current Positions" (open Polymarket positions).
- Default UI backgrounds white (scaffold/cards); use colored fills only when explicitly requested (e.g. convergence thresholds).
- On the web build, include a link to the GitHub Actions refresh workflow so data refresh can be triggered manually.

## Learned Workspace Facts

- This repo is a Flutter app (`app16_lowest`) for Polymarket low-temperature weather markets (`https://polymarket.com/weather/low-temperature`): Windows desktop uses live Gamma/CLOB; GitHub Pages web reads same-origin static `data/markets.json` (avoids browser CORS) with Actions refreshing that snapshot about every 5 minutes. The snapshot also preloads WRH station temperature series so expand charts/tables work without browser calls to weather.gov or Open-Meteo.
- Manual Refresh and the 1-minute auto-refresh must reload markets and odds from Polymarket while preserving filters and the selected market (Windows live path).
- "Time to EOD" is hours and minutes until 23:59 in the market city’s local timezone—not market close/resolution time and not a stale calendar-day "EOD passed" when local evening still remains.
- Temperature-outcome / chance stats must stay consistent with Polymarket’s site (wrong % or inventing a winner when Polymarket shows "-" is a bug); on wide spreads prefer mid when that matches Polymarket’s large %, over Buy Yes ask or a conflicting last trade alone.
- Current Positions loads the Polymarket Data API for the configured public proxy wallet `0x8cEF3c1B592953D61EEE2bC9375C5944A8926B6d`.
- Sites tab lists unique cities A–Z with each city’s resolution-source URL (from Gamma `resolutionSource` or Rules/description); show °C/°F badges from outcome labels; for `weather.gov/wrh/timeseries` sources title as `City - siteId` (e.g. `Guangzhou - zggg`); otherwise show a red "Unique Resolution Source" badge.
- Opening weather.gov WRH timeseries links for °C markets appends `&units=metric`; °F markets leave the URL unchanged.
- Expanded Low Markets rows show an hourly temperature chart only for `weather.gov/wrh/timeseries` resolution sites: observed temps before now, forecast after, city-local from 00:00 through next-day 00:00 inclusive.
- Forecast preference for charts: `api.weather.gov` hourly first, then Open-Meteo NBM (`ncep_nbm_conus`) for US fallback, then default Open-Meteo as last resort / non-US.
- Hourly chart styling: black temperature line; blue minimum horizontal line and stars; orange maximum horizontal line and stars; red vertical line at current time.

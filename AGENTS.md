## Learned User Preferences

- Prefer a dense Windows UI: tighter spacing, smaller market heading fonts, and no top banners (e.g. remove "Low Temp Markets") that waste vertical space.
- Avoid redundant labels; if a degree already shows its percentage (e.g. "14° 99%"), do not also show a separate "% Yes" style label; format top outcomes as "x% @ yC" (e.g. "70% @ 26C").
- Always hide markets past local EOD (no toggle), sort by time-to-EOD, always auto-refresh every 1 minute (no checkbox), and show all active market dates (no date filter).
- Use sliders for Min convergence (1% steps) and Min time-to-EOD (15 min steps; default ≥ 0 min showing everything), not multi-select buttons.
- Outcome percentages and Buy Yes / Buy No must match Polymarket’s live display (including "-" / unavailable when Polymarket shows no odds); chance % is Polymarket’s large percentage (use mid/last on wide bid-ask), not Buy Yes ask.
- Accordion expand: only one market open at a time; no blue city badge; when expanded, show Buy Yes and Buy No.
- Color rules: date badges vary by calendar day but never red/green/yellow/blue; EOD badge red if <1h, orange if <3h, else blue; market row / top-outcome chip / temperature rows use ≥95% green, ≥90% yellow, ≥80% cyan, else white.
- Strategy dropdown: "Show All" (no filter) vs "Find Locked Market (≥ 90%) with No's Opportunities" (at least one temperature with chance ≥ 90%, and at least one other with chance < 90% where Buy No > 1¢ and not "--").

## Learned Workspace Facts

- This repo is a Flutter app (`app16_lowest`) aimed at Windows for listing Polymarket low-temperature weather markets from `https://polymarket.com/weather/low-temperature`.
- Manual Refresh and the 1-minute auto-refresh must reload markets and odds from Polymarket while preserving filters and the selected market.
- "Time to EOD" is hours and minutes until 23:59 in the market city’s local timezone—not market close/resolution time and not a stale calendar-day "EOD passed" when local evening still remains.
- Temperature-outcome / chance stats must stay consistent with Polymarket’s site (wrong % or inventing a winner when Polymarket shows "-" is a bug); prefer mid/last on wide spreads over Buy Yes ask alone.

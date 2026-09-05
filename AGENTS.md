## Learned User Preferences

- Prefer a dense Windows UI: tighter spacing, smaller market heading fonts, and no top banners (e.g. remove "Low Temp Markets") that waste vertical space.
- Avoid redundant labels; if a degree already shows its percentage (e.g. "14° 99%"), do not also show a separate "% Yes" style label.
- Default list behavior: hide markets past local EOD, sort by time-to-EOD, and enable auto-refresh every 1 minute.
- Prefer a slider to filter High/Mid/Low temperature-convergence, not multi-select buttons.
- Outcome percentages and Buy Yes / Buy No must match Polymarket’s live display (including "-" / unavailable when Polymarket shows no odds).
- When expanding a city, show Buy Yes and Buy No; support filtering out sub-rows where both are 0¢ or "--".
- Prefer clear color contrast on the market list for readability.

## Learned Workspace Facts

- This repo is a Flutter app (`app16_lowest`) aimed at Windows for listing Polymarket low-temperature weather markets from `https://polymarket.com/weather/low-temperature`.
- Manual Refresh and the 1-minute auto-refresh must reload markets and odds from Polymarket while preserving filters and the selected market.
- "Time to EOD" is hours and minutes until 23:59 in the market city’s local timezone—not market close/resolution time and not a stale calendar-day "EOD passed" when local evening still remains.
- Temperature-outcome stats should be derived so they stay consistent with Polymarket’s site (wrong % or inventing a winner when Polymarket shows "-" is a bug).

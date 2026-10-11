# Play Console metrics

The release plan (docs/design/README.md) reads retention when 1.13 reaches 100% and again about 4 weeks later, before 2.0 ships. There is no in-app telemetry, so these numbers come from Play Console only.

## 1.13.0+28 at 100% (recorded 2026-10-04)

1.13.0 reached 100% in production on 2026-10-04. It replaced 1.9.2, released 2026-08-19. Play's statistics lag by several days, so the daily rows end on Sep 27.

**Dashboard, last 28 days compared with the 28 days before:**

| Metric | Value | Change |
|---|---|---|
| Device acquisitions | 172 | +266% |
| Device first opens | 95 | +375% |
| Monthly active devices | 102 | +252% |
| Crash rate, ANR rate, rating | not shown | too little data |

**Installed audience** is about 98 (late September). It was about 32 on Sep 4.

**Daily DAU/MAU** (Compare to peers tab, all countries). The peer group, House & home, showed no figures.

| Day | DAU/MAU |
|---|---|
| Sep 18 | 23.81% |
| Sep 19 | 12.86% |
| Sep 20 | 9.33% |
| Sep 21 | 16.85% |
| Sep 22 | 17.82% |
| Sep 23 | 5.71% |
| Sep 24 | 9.35% |
| Sep 25 | 3.81% |
| Sep 26 | 5.5% |
| Sep 27 | 19.55% |

The 7-day mean for Sep 21 to 27 is **11.2%**. With about 100 monthly users, one day can move by 10 points, so compare 7-day means, not single days.

**User loss and retention:** Play has no monthly user-loss metric for this app. Its 2-, 3-, 7- and 14-day device retention all show "Data unavailable", because there are too few users. Use installed audience and DAU/MAU instead.

## Next reading

Around 2026-11-01, 4 weeks after 1.13 reached 100%, record the same table. Then compare the Sep 21–27 mean with the last full week before 2.0 ships. Outreach on 2026-10-04 (Z2M Discussion #33283, the HA thread update, Reddit, awesome-mqtt #166) will also lift acquisitions in that window, so read it as 1.13 and outreach together.

## All-time new users (read 2026-10-08)

Play Console › Statistics › User acquisition › New users, monthly, all countries:

| Month | New users |
|---|---|
| May 2026 | 17 |
| Jun 2026 | 2 |
| Jul 2026 | 7 |
| Aug 2026 | 51 |
| Sep 2026 | 181 |
| Oct 1–7 2026 | 58 |
| **Total** | **316** |

Forecast for the Play "1,000+ downloads" badge: around 2027-01-01 at October's ~8 a day; early December 2026 if the 2.0 launch adds ~150 and the pace reaches ~10 a day. Re-read with the 2026-11-01 table.

## Reading of 2026-10-11 (2.3.1 live, 2.3.2 in review)

Dashboard, last 28 days compared with the 28 before:

| Metric | Value | Change |
|---|---|---|
| Device acquisitions | 282 | +432% |
| Device first opens | 108 | +286% |
| Monthly active devices | 167 | +391% |
| Installed audience (Oct 8) | 160 | 98 in late Sep, 32 on Sep 4 |

Pace: about 10 acquisitions a day; 38% of acquisitions open the app; the installed audience grows by roughly 60 a month, about a quarter of acquisitions. Top countries by installed audience: France 17, Russia 16, Germany 14, Israel 14, then the US, Netherlands, UK, Australia, Brazil, Poland.

### One-year estimate (to October 2027), made 2026-10-11

Assumes releases keep coming at the current rhythm and the announcement posts go out. Cumulative installs = Play acquisitions to date (~350) plus the next 12 months.

| Scenario | Monthly acquisitions | Cumulative installs | Installed audience |
|---|---|---|---|
| Low: pace stays flat | 300 | ~4,000 | 700–900 |
| Base: +8% a month (Play Explore + posts + translations) | 300 → 750 | ~6,000 | 1,100–1,400 |
| High: a Z2M docs listing or a post that lands, +15% a month | 300 → 1,600 | ~9,000 | 2,000–2,500 |

Levers that decide which row: activation (the 38% first-open rate), a mention in the Zigbee2MQTT docs or README, IzzyOnDroid/F-Droid, Russian-speaking channels (Russia is the #2 country with a fresh translation), and ratings count (4 so far). Re-read at the 2026-11-01 table.


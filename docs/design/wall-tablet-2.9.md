# Wall tablet: what it does when nobody touches it (2.9)

Decided 2026-10-17 in two rounds; the user took every recommendation. Builds
on Wall display and the Kiosk lock ([kiosk-2.6.md](kiosk-2.6.md)) and on Pro
([history-2.7.md](history-2.7.md)). Words follow [CONTEXT.md](../../CONTEXT.md).

## Why

- Wall tablets keep coming up in the Home Assistant community: dashboards
  are slow on cheap panels, every panel is "its own little project", and
  Home Assistant 2025.12 removed the per-device default dashboard ("a total
  nightmare", forum). Families want something simple on the wall
  (Reddit's most-commented complaint theme). Research of 2026-10-16.
- ZigDash already has the per-tablet part: in kiosk each tablet keeps its
  own Home and dashboard and comes back to them after a restart (2.6). What
  is missing is what the tablet does while nobody is touching it.
- Pro (one-time, 7.99 EUR) needs a reason beyond history. Waking on a Zigbee
  motion sensor is something no web-based wall panel does, because ZigDash
  already sees every sensor live.

## Decisions

1. **Four features:** wake on motion, a screensaver, a night schedule and
   alarm takeover. No ambient light sensor (native work per device; the
   night schedule covers most of it). No new start-dashboard feature: kiosk
   already pins one per tablet.
2. **"When no one touches it"** replaces "Dim after". Two parts: **After**
   1, 5 or 15 minutes, or never; **Show** Dimmed dashboard (today's
   behaviour), Clock, Clock and readings, or Black. Anyone who has Dim after
   set today keeps exactly that (same key, Show = Dimmed). Clock and Clock
   and readings move slowly across the screen against burn-in; Black is for
   OLED screens and turns the brightness down too.
3. **Readings on the screensaver:** 1 to 3, picked from the reading tiles of
   that dashboard (temperature, humidity, anything a Reading tile shows), so
   there is nothing new to configure. Large, with the name under each.
4. **Wake on motion:** in the sheet the user picks one or more sensors of
   that Home that report `occupancy` or `presence`, and optionally door or
   window contacts (`contact` false, i.e. opened). Any of them turning on
   wakes the tablet as a touch does: full brightness, dashboard shown, the
   idle timer restarts. Touch still wakes it. No sensor picked: as today.
5. **Night:** from-to hours (default 23:00 to 07:00, off until chosen).
   During the night the idle screen is **Black** whatever Show says, also
   when night starts while the clock already shows (a timer at each
   boundary; at the end of the night an idle screen goes back to Show). A touch
   wakes it normally; motion wakes it only to low brightness (about 15%) so
   a hallway isn't lit at 3 a.m.; an alarm wakes it fully. Phone time zone.
6. **Alarm takeover:** reads the devices of the tablet's Home directly, no
   Node-RED and no Alerts setup needed. Fires when a device reports
   `water_leak`, `smoke`, `gas` or `carbon_monoxide` true. Full screen,
   red, the device's name and what it reports, full brightness, over the
   screensaver, night and kiosk. **OK** dismisses it; it fires again only
   after that sensor has cleared and triggered again. A sound, on by
   default, can be turned off in the sheet. Works while ZigDash is open on
   screen with Wall display on; it is not a replacement for Alerts, which
   reach phones anywhere, and the sheet says so in one line.
7. **Free and Pro.** Everything that exists stays free. Free: Clock, Black
   (and Dimmed). **Pro:** Clock and readings, wake on motion, night, alarm
   takeover. A locked row shows a small Pro badge; tapping it explains Pro
   once, in the sheet, no pop-ups and no reminders. GitHub, IzzyOnDroid
   and F-Droid builds have everything (no billing code), as in 2.7.
8. **No Play release until Pro can be bought.** If the payments profile and
   the `zigdash_pro` product aren't ready when 2.9 is built, the Play
   release waits; the GitHub release ships. Never ship Pro features free on
   Play to lock them later, and don't build hidden-Pro again.
9. **Everything works with Wall display on, with or without the Kiosk
   lock.** All settings are on the tablet, per dashboard, like 2.6's
   (shared preferences, `wall_*_<dashboardId>`); nothing goes to the
   broker, so two tablets of one Home can differ.
10. **Where:** the Wall display sheet (⋮ › Wall display) gains sections:
    When no one touches it, Wake on motion, Night, Alarms.
11. **Measured.** The `kiosk` feature event (sent when the wall display is
    set up) gains `idle_show` (dim, clock, readings, black), `motion` (yes,
    no), `night` (yes, no) and `alarms` (yes, no). New event `alarm_shown`
    with only `kind` (leak, smoke, gas, co). Never names. `store/PRIVACY.md` (the canonical
    policy) gets the rows; `docs/privacy.md` is a stale copy from before
    2.7 and isn't kept.

## Build notes (not yet decided in detail)

- `wall_display.dart`: `WallDimSetting` keeps its key for After; new
  `WallIdleShowSetting`, `WallNightSetting` (from, to), `WallMotionSensors`
  (list of device IEEEs), `WallAlarmSetting` (on, sound). `WallDisplayScope`
  owns one idle state machine: awake → idle (show) → woken by touch, motion
  or alarm; night changes what idle shows and how bright motion wakes.
- Motion and alarms subscribe through the Home's existing device state
  streams; no new MQTT subscriptions beyond what the dashboard holds,
  except the picked sensors and the Home's alarm-capable devices.
- Screensaver: a full-screen overlay inside the scope, above the dashboard,
  below the alarm. Sound: a short looping tone from the app's assets
  (no new permission).
- Pro: `proProvider` gates the four rows; `foss` flavor always unlocked.
- Tests: idle machine with fake clock (touch, motion, night, alarm order),
  sheet rows locked/unlocked, alarm fires once per trigger, goldens for the
  clock, readings and alarm screens in light and dark.
- Strings ×11; changelog; privacy policy rows; store listing line and a
  wall-tablet screenshot with the clock.

## Not in 2.9

Ambient light sensor, turning the screen fully off and on (needs device
admin), camera presence, weather on the screensaver (would need a cloud
service), alarms from Alerts (Node-RED) on the tablet.

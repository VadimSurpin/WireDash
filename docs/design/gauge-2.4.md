# Gauge: a reading tile as a half arc (2.4)

Decided 2026-10-11 in a six-question round; the user took every
recommendation. Words follow [CONTEXT.md](../../CONTEXT.md) (**Reading
tile**, **Tile size**). Rival reviews (IoT MQTT Panel, 2026-10-10 scrape)
ask for gauges with colour bands and for a plain value display; one tile
with two styles covers both.

## Decisions

1. **A style of the Reading tile, not a new tile type.** A Reading tile
   already binds one numeric value with its unit to a device, is created in
   one tap from a device page, and decodes from JSON config. `ReadingConfig`
   gains `style` (`value`, the default, or `gauge`), `min`, `max` and
   `bands`. Every tile saved before 2.4 decodes unchanged; there is no
   migration, no new picker entry and no new type label in 11 languages. The
   roadmap's "17th panel type" wording was wrong on both counts (there were
   already 17) and is superseded by this.
2. **Band colours come from the theme's state roles, never a picker.** Each
   band is Normal, Good or Attention. Good uses the healthy role, Attention
   the attention role; amber stays the "on" colour and never means warning.
   The band tints the track in the role's container colour and shows
   through the value arc once the value has passed it, so the whole scale
   reads at a glance; the value arc draws in the role's content colour, or
   ink in a normal band or none.
3. **Defaults.** The device's expose range wins when Zigbee2MQTT declares
   one. Otherwise, by what the reading is (`gaugeDefaults`): battery 0 to
   100 with Attention under 20; humidity 0 to 100 with Good 30 to 60;
   temperature 0 to 40 °C (32 to 104 °F); power 0 to 3000 W; anything else
   0 to 100. Bands default to none except battery and humidity. Everything
   is editable. A reading tile created from a device page stores these at
   creation, so switching to Gauge later needs no typing; a tile from before
   2.4 or a custom-topic reading gets them the first time it is switched.
4. **The style is chosen in the tile editor only** (long-press, Edit, "Show
   as": Value or Gauge). Adding from a device page stays one tap and makes a
   value tile. A long-press "Show as gauge" can follow if asked for.
5. **Layout.** A Small tile by default, like a value tile: a half arc on
   top, the value with its unit inside the arc, the name underneath. Rows
   grow to fit. Wide and Full keep the same drawing, centred: the arc is
   a fixed 100 dp tall (`gaugeHeight`), so rows stay the same height, and at most twice as wide. The arc never mirrors
   in Hebrew, like a dial; the value is an LTR run as readings are already.
6. **Release.** 2.4.0 ships the gauge, the community card and the "close
   all" covers action. History moves to 2.5 unless the poll says otherwise.

## Out of scope

- History view: there is none yet; the gauge lives on the dashboard only.
- Widgets, Quick Settings and Device Controls: reading tiles are not offered
  there today, so neither is the gauge.
- Stale-value styling: reading tiles don't distinguish stale values yet;
  the gauge inherits that.

## Code

- `lib/features/panels/models/panel_config.dart`: `ReadingStyle`,
  `GaugeTone`, `GaugeBand`, `gaugeMaxBands` (3), the new `ReadingConfig`
  fields. Unknown style or tone names fall back; bands cap at three.
- `lib/features/panels/models/gauge_defaults.dart`: `gaugeDefaults`.
- `lib/features/panels/widgets/gauge_panel.dart`: `GaugeArc` (painter,
  animated with `SignalMotion.stateChange`), `gaugeBandFor`,
  `gaugeFraction`. `ReadingPanel` picks it for `style == gauge`.
- `lib/features/devices/device_tiles.dart`: `readingConfigFor(feature)`
  fills the range and bands at creation.
- Editor: `panel_form_screen.dart` (`_readingStyle`, `_readingMin`,
  `_readingMax`, `_bandRows`, `_setReadingStyle`) and
  `panel_form_screen.fields.dart` (`_gaugeFields`).
- Demo Home: a humidity gauge on the Living room sensor.
- Strings: `readingShowAs`, `readingStyle*`, `gauge*` in all 11 ARBs.
- Tests: `reading_config_test`, `gauge_defaults_test`, `gauge_panel_test`,
  `reading_form_gauge_test`; the device-tiles golden gains a gauge.

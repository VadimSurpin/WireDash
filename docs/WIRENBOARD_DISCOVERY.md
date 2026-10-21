# Wiren Board discovery

ZigDash can discover devices published by Wiren Board drivers and virtual
devices directly from the MQTT broker. No additional server or Zigbee2MQTT
converter is required. The connection must allow subscriptions to:

```
/devices/+/meta/#
/devices/+/controls/+/meta/#
```

Create an MQTT connection and a dashboard, then choose **Add tile → Wiren
Board**. Devices start collapsed and are grouped into added modules and controller
built-ins. Search matches both device and control names. Use the + button next
to a device to add it as one panel, or expand it and select an individual
control. Review the suggested tile and save it. Tap a whole-device panel to
open its full, scrollable set of controls. The discovery screen also has a Zigbee2MQTT source selector.

Discovery listens for retained metadata and subsequent changes. It supports
both current JSON `/meta` messages and legacy `/meta/type`, `/meta/readonly`,
`/meta/name`, `/meta/min`, `/meta/max`, and `/meta/order` messages. JSON fields
take precedence over legacy fields, regardless of message order. Hidden
controls are omitted. Titles use the app's language, then English, Russian,
another available translation, and finally the topic identifier. Clearing a
retained metadata topic removes that metadata from the discovery list.

A whole-device panel caches its metadata for offline use and follows live
metadata when available. Its controls use the same connection and read-only
checks as individual tiles. A whole-device panel creates one dashboard row;
its controls are not separate stored tiles.

Built-in grouping uses exact standard device IDs (`hwmon`, `wb-gpio`, `wb-adc`,
`power_status`, etc.). Other module and virtual device IDs appear under added
modules. MQTT metadata does not identify the physical controller for arbitrary
custom device names. Expansion state is preserved while metadata updates.

Individual controls use these suggested tiles:

| Control | Suggested tile |
| --- | --- |
| Writable switch | Toggle, raw `1` / `0` commands |
| Read-only switch or alarm | LED indicator |
| Write-only switch | Explicit `0` / `1` choices |
| Pushbutton | Button, raw `1` command |
| Writable value/text with an enum | Choices with translated labels |
| Writable range | Integer slider using published minimum/maximum (defaults 0–255) |
| Read-only numeric control | Reading with units, including legacy sensor types |
| Other writable numeric/text control | Raw text input |
| Other control, including RGB | Read-only text log |

State is read from `/devices/<device>/controls/<control>` and commands go to
that exact topic plus `/on`. The leading slash and identifiers (including
spaces) are preserved. Commands are not retained. Values are scalar payloads,
without Z2M's JSON wrappers. For numeric enums, hexadecimal metadata keys are
converted to decimal command/matching values.

The tile form remains editable. Numeric text input leaves validation of limits
and precision to the device driver. Dedicated RGB/time editors, device error
indicators, automatic setup probing, and WB entries in the Zigbee2MQTT Devices
tab are not included. Discovery updates do not overwrite saved tile settings
or delete dashboard tiles; revisit discovery to add newly published controls.

The protocol reference is the official
[Wiren Board MQTT conventions](https://github.com/wirenboard/conventions).

## Verification

```
flutter analyze
flutter test test/features/discovery test/features/panels/panel_form_topics_test.dart test/features/panels/add_tile_screen_test.dart
```

Tests exercise JSON and legacy retained metadata, updates/removal, malformed
messages, translated titles, read-only/hidden flags, scalar payloads and topic
composition, cached wildcard replay, subscription cleanup, source selection,
and creating/editing suggested configurations through the actual tile form.
Whole-device tests check config round-trips, read-only controls, scalar
commands, cached offline controls, grouping, search, and preserved expansion.

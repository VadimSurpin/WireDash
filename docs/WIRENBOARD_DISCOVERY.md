# Wiren Board discovery

ZigDash can discover devices published by Wiren Board drivers and virtual
devices directly from the MQTT broker. No additional server or Zigbee2MQTT
converter is required. The connection must allow subscriptions to:

```
/devices/+/meta/#
/devices/+/controls/+/meta/#
```

Create an MQTT connection and a dashboard, then choose **Add tile → Wiren
Board**. Expand a device and select a control. Review the suggested tile and
save it. The discovery screen also has a Zigbee2MQTT source selector.

Discovery listens for retained metadata and subsequent changes. It supports
both current JSON `/meta` messages and legacy `/meta/type`, `/meta/readonly`,
`/meta/name`, `/meta/min`, `/meta/max`, and `/meta/order` messages. JSON fields
take precedence over legacy fields, regardless of message order. Hidden
controls are omitted. Titles use the app's language, then English, Russian,
another available translation, and finally the topic identifier. Clearing a
retained metadata topic removes that metadata from the discovery list.

Each control becomes a separate tile:

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
and saving suggested configurations through the actual tile form.

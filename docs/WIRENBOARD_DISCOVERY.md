# Wiren Board discovery

ZigDash can discover devices published by Wiren Board drivers and virtual
devices directly from the MQTT broker. No additional server or Zigbee2MQTT
converter is required. The connection must allow subscriptions to:

```
/devices/+/meta/#
/devices/+/controls/+/meta/#
```

Create an MQTT connection and a dashboard, then choose **Add tile → Wiren
Board**. Discovered non-built-in modules are added automatically as whole-device panels,
with no duplicates on repeated discovery. This works in initial broker setup,
the manual connection wizard, and the dashboard discovery screen. Built-ins
are listed in All devices and can be added manually.

In **All devices**, each section can be collapsed independently. Controller
built-ins and Wirenboard Z2M devices start collapsed; added modules and native
Zigbee2MQTT devices start expanded. Search reveals matching devices and
properties inside collapsed sections, then restores their expansion state when
cleared. Device rows expand into a property tree. Use the + button next to a
property to add it as a standard tile, or the device's + button to add the whole
device. The add sheet asks for a label and target dashboard. The discovery
screen also has a Zigbee2MQTT source selector.

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

Built-in grouping recognizes controller service IDs starting with `system__`,
cloud/network service drivers, and exact standard device IDs (`hwmon`, `wb-gpio`, `wb-adc`,
`power_status`, etc.). Other module and virtual device IDs appear under added
modules. MQTT metadata does not identify the physical controller for arbitrary
custom device names. Expansion state is preserved while metadata updates.

Cloud status, network connections, the KNX gateway, battery and alarms belong to
controller built-ins. They are not automatically added as external modules.
WB copies of Zigbee2MQTT devices appear under **Wirenboard Z2M devices** in
All devices, discovery, setup and dashboard sections. Both `wb-mqtt-zigbee`
and `wb-zigbee2mqtt` driver metadata identify a mirror directly. Legacy
wb-rules copies are matched against the retained native `bridge/devices` list
using device IDs/friendly names (the bridge's first-slash substitution) and
IEEE addresses; translated display labels are not used. A known different
physical-device driver takes precedence over a matching friendly name.
The native list is optional and never delays WB-only discovery.

Rediscovery updates sections of existing automatically grouped panels,
including older built-in panels imported as modules, without duplicating
panels or changing custom labels, property selections or user-defined sections.
Automatic section names are recognized across all supported languages.

When JSON metadata is present, it is the complete metadata snapshot. Missing
fields use WB defaults (including writable by default); stale legacy subtopics
cannot override them. Legacy-only devices remain supported.

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
| Other writable control, including RGB and local time | Raw text input |
| Other read-only control | Read-only text log |

State is read from `/devices/<device>/controls/<control>` and commands go to
that exact topic plus `/on`. The leading slash and identifiers (including
spaces) are preserved. Commands are not retained. Values are scalar payloads,
without Z2M's JSON wrappers. For numeric enums, hexadecimal metadata keys are
converted to decimal command/matching values.

The tile form remains editable. Numeric text input leaves validation of limits
and precision to the device driver. Dedicated RGB/time editors, device error indicators are not included. Discovery updates do not overwrite saved tile settings
or delete dashboard tiles; revisit discovery to add newly published controls.

The protocol reference is the official
[Wiren Board MQTT conventions](https://github.com/wirenboard/conventions).

## Verification

```
flutter analyze
flutter test test/features/discovery test/features/devices/devices_screen_test.dart test/features/panels/wirenboard_device_panel_test.dart test/features/onboarding/setup test/app/wirenboard_localization_test.dart
```

Tests exercise JSON and legacy retained metadata, updates/removal, malformed
messages, translated titles, read-only/hidden flags, scalar payloads and topic
composition, cached wildcard replay, subscription cleanup, source selection,
and creating/editing suggested configurations through the actual tile form.
Whole-device tests check config round-trips, read-only controls, scalar
commands, cached offline controls, grouping, search, and preserved expansion.

## Device panels

Wiren Board and Zigbee2MQTT devices use the same dashboard card renderer:
class icon, switch quick actions where applicable, device label, readings and
state summary, with the same shapes, colors and typography. Tap a WB card to
open its draggable, scrollable controls sheet. WB commands still use scalar
payloads on each control's own `/on` topic; read-only controls cannot send
commands.

New tiles can represent one property or a whole device. Creating a selected
subset as one device panel is unavailable for now. Previously saved subset
panels remain usable and keep their selections and labels on rediscovery.

## Customize a saved panel

Whole-device switches have their own labels. Open a tile's menu and choose
Edit, then use **Card contents** to choose which properties appear and enter
optional custom labels. These settings belong to that saved panel; they do not
rename MQTT controls or affect other panels. Open the card to access all device
controls, including properties hidden from the card. **Reset card contents and
labels** restores the defaults. The same editor supports native Zigbee2MQTT
panels. Discovery refreshes keep saved visibility and labels.

When adding an individual WB property, choose **Widget type** before adding it.
The suggested widget is selected initially. Available alternatives depend on
the control: numeric readings can use a reading or progress bar; writable
ranges can also use a slider or input; switches offer toggles, indicators and
explicit choices where supported. Every writable control offers text input for
raw scalar commands, including RGB, local time and custom control types.
Read-only controls offer display widgets.
The discovery tile form also offers this selector, with editable widget
settings. Switching widgets preserves the label and WB scalar MQTT topics.

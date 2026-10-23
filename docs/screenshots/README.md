# README screenshots

These PNGs are exported from WireDash's reviewed Linux golden snapshots. They
show actual Flutter app widgets in the default Wiren Board green theme, using
demo MQTT devices and values. They are not photographs or captures from a live
broker, and contain no real connection credentials.

| Image | Source snapshot | Variant |
| --- | --- | --- |
| `dashboard-light.png` | `device_tiles_phone.png` | English, light, 1x text |
| `dashboard-dark.png` | `device_tiles_phone.png` | English, dark, 1x text |
| `device-controls.png` | `device_page_phone.png` | English, light, 1x text |
| `devices.png` | `devices_tab_phone.png` | English, light, 1x text |
| `wirenboard-panel.png` | `wirenboard_device_card.png` | English, light, 1x text |

The exporter removes the 31px test-case header and selects the phone viewport
(or the WB card) from the scenario grid. It does not recolour the UI, add mock
phone chrome, or fabricate widgets. Some source scenarios are taller than the
README viewport; their lower content is cropped.

After changing the UI, refresh and review the affected goldens, then export:

```bash
tool/flutter pub run tool/readme_screenshots.dart
```

The inputs live in `test/goldens/goldens/linux/`. If using sparse checkout,
include those snapshots before running the exporter. Source scenarios are in
`test/goldens/device_tiles_golden_test.dart`,
`test/goldens/navigation_golden_test.dart`, and
`test/goldens/wirenboard_device_golden_test.dart`.

# Before-display expressions

When adding an individual WB property, or editing a tile, expand
**Before display (JavaScript)**. For a whole WB or
Zigbee2MQTT device, use the same field below each property in **Card contents**.
Settings belong to that saved tile; rediscovery preserves them. Clearing the
expression restores the original presentation. The editor can test an
expression with a sample value before saving.

`value` is the incoming value after JSON-path extraction. WB scalar payloads
are usually strings, so use `Number(value)` for numeric methods. Return one
number, string, boolean or `null`. Strings retain their formatting, including
trailing zeroes; `null` displays as a dash. The widget still appends its unit.

| Purpose | Expression |
| --- | --- |
| Divide by 100 | `Number(value) / 100` |
| Two decimal places | `Number(value).toFixed(2)` |
| Scale and keep two decimal places | `(Number(value) / 10 ** 3).toFixed(2)` |
| Round to an integer | `Math.round(Number(value))` |
| Custom state label | `Number(value) ? 'Running' : 'Stopped'` |
| Handle a missing value | `value == null ? null : Number(value).toFixed(1)` |

Expressions format readouts. Slider positions, switch states, commands,
retained MQTT messages, stored history, availability and freshness checks keep
their original values. Choice widgets may match their selected option against
the expression result, but send the configured option payload. An expression
does not create an inverse transform for writes. Whole-device control inputs
keep raw values; the formatted current value is a separate readout.

Android and the native desktop/mobile builds use QuickJS through the pinned
JSF dependency. Each evaluation has its own realm, a 15 ms execution budget,
16 MiB JavaScript heap limit and 512 KiB stack limit. Networking and timer host
functions are unavailable. Expressions are limited to 4,096 characters, input
to 64 KiB and returned text to 16 KiB. A bounded cache avoids reevaluating the
same expression and input during rebuilds.

Invalid syntax is reported by the editor. Runtime errors, timeouts, nonfinite
numbers and unsupported results retain the original value and show an error
indicator. This version deliberately falls back to raw values in the web app;
bounded expression execution is supported by native builds only.

For Linux tests, run `flutter pub get` followed by
`python3 tool/build_display_js_native.py`, then set `JSF_LIBRARY_PATH` to the
printed shared-library path when running Flutter tests. CI builds that exact
library from the locked package source and also publishes it as the
`display-js-native-linux` artifact. Android builds it through the FFI plugin.
The upstream QuickJS MIT notice is bundled and appears in About's licenses.

# Wiren Board curtain mode: research and proposed support

Researched and implemented on `feat/wirenboard-curtain-controls`, 2026-10-26.
Automated checks do not replace testing with an actual module and its firmware.

## Device protocol

WB's curtain mode combines adjacent outputs: K1/K2, K3/K4 and K5/K6 on
six-output modules. The relay firmware provides mutual exclusion, reversal
dead time and separate opening/closing run times. Configure these in the
controller's device settings, under curtain/actuator control. The feature
requires a compatible module and firmware; the register map introduces it at
firmware 1.21.0. A configured run time of zero disables its timeout on firmware
1.24.0 and later, so the app must not assume every drive stops after a fixed
number of seconds.

Sources: [WB-MR6C v.3 manual](https://wiki.wirenboard.com/wiki/WB-MR6C_v.3_Modbus_Relay_Modules),
[relay register map, actuator control](https://wiki.wirenboard.com/wiki/Relay_Module_Modbus_Management).

The WB driver exposes writable scalar switch controls named `Curtain N Open`
and `Curtain N Close` when the corresponding pair is in curtain mode. The
ordinary K outputs become read-only in this mode. Use these dedicated curtain
controls, preserving the module's own interlocking and timers.

Source: [WB driver template](https://github.com/wirenboard/wb-mqtt-serial/blob/351defb44dbe35f99e371ccde0fb9d0675e6e0f4/templates/config-wb-mr6cv3.json.jinja).

For a discovered module ID `wb-mr6cv3_12`, drive 1:

| Action | Command topic | Scalar payload |
| --- | --- | --- |
| Open | `/devices/wb-mr6cv3_12/controls/Curtain 1 Open/on` | `1` |
| Close | `/devices/wb-mr6cv3_12/controls/Curtain 1 Close/on` | `1` |
| Stop | Both of the above topics | `0` on each |

Subscribe to the same two control topics **without** `/on` for feedback.
Starting a direction is a single write of `1`, not a momentary `1`/`0` pulse
or a held phone gesture. The module resets the corresponding curtain control
when its timed run finishes; writing `0` interrupts it. A reversal should
request the opposite curtain direction and leave the dead time to firmware.
Commands must not be retained or queued for replay after reconnecting.

Source: [WB support explanation of MQTT curtain control](https://support.wirenboard.com/t/wb-mr6c-v-rezhime-shtor-kak-upravlyat-po-mqtt/18531).

## Widget and feedback

Each cover has a **Wait for MQTT feedback** setting (on by default for existing
configurations). Switch it off for a stateless command button: every tap sends
the configured command, shows a spinner for one second, then restores its
normal icon. This mode does not subscribe to state, show relay highlighting,
position controls, stale indicators or confirmation warnings. Repeated taps
remain enabled and restart the one-second animation; they do not replay any
commands automatically. The setting is available in both tile creation and
editing and is included in dashboard backups.

Extend the existing **Cover** tile with a WB paired-topic binding. Use one
compact card with Open and Close buttons by default. Each of Open, Close and
Stop has configurable visibility, title and icon. Roller and gate icons include
an explicit partially-open gate. Existing JSON covers retain their three
buttons by default. The
existing Cover implementation assumes a single command topic and a JSON state
message; it cannot bind the two WB controls through configuration alone.

Recommended feedback behavior:

| Event or received state | Presentation |
| --- | --- |
| User taps a direction | Immediately show a pending spinner on that button |
| User taps the same button again, including while pending | Publish another `1` on the same command topic; restart the pending confirmation window |
| Fresh Open=`1`, Close=`0` | Replace the pending spinner with the configured icon and highlight Open |
| Fresh Open=`0`, Close=`1` | Replace the pending spinner with the configured icon and highlight Close |
| Both controls=`0` | Clear direction highlighting |
| Stop tapped | Show pending feedback until both reported states are zero |
| Feedback missing, invalid or disconnected | Show unknown/stale or not-confirmed state |

Keep the pending command separate from the reported movement state. A fresh
binary update on the commanded control removes the spinner, including `0`:
a pulse can already have reset before the next feedback message. Highlight
only the reported active relay, without inferring gate position. This also
reflects actions initiated by a wall button or another MQTT client.

Buttons stay tappable while waiting for feedback. Every explicit direction tap
sends `1` again; it never changes to `0` based on the current state. A gate
controller wired for step-by-step operation can then perform its own
open/stop/close cycle. The app does not simulate that cycle or send extra pulses.

Confirm commands using a newer state message in the current connection
generation, not MQTT PUBACK or a cached value. Subscribe before issuing the
command. Time out pending confirmation explicitly; do not turn missing
feedback into a successful stop. Do not automatically resend motion commands
on reconnect.

Two topics update independently, so direction changes may briefly produce an
inconsistent combined snapshot. Tolerate message ordering and use a switching
state while confirmation is pending. Stop is available when enabled by the user. The curtain flags
describe the module's operation, not measured motor movement or end position.
Both zero means stopped; it does not establish fully open or fully closed.
Hide the percentage slider and position presets without actual position data.

## Integration points

- Detect complete `Curtain N Open` / `Curtain N Close` pairs within one
  discovered device, using control IDs rather than translated titles. Offer
  each pair as one Cover tile, with a user-supplied label/icon.
- Preserve access metadata. Never override the read-only K channels to
  implement this feature, or assume that any two ordinary relays form a cover.
- Add an explicit WB binding to the cover configuration: module ID, drive
  number, and the two feedback/command topics. Preserve existing JSON cover
  configurations and their behavior.
- Use `panelValueSnapshotProvider` for timestamps and connection freshness.
  Extend `CoverPanel` or dispatch to a WB-specific implementation while keeping
  the user-facing tile type Cover.
- No Node-RED or wb-rules bridge is required for this direct MQTT binding.

The current single-property Toggle tile already supports WB scalar `1`/`0`
commands and different on/off icons driven by MQTT. Two such tiles can expose
the curtain controls today, but they do not provide a combined cover card,
pending-command feedback or configurable visibility for the complete pair.

## Validation before delivery

Exercise opening and closing through automatic switch-off, early Stop,
direction reversal, wall-button changes, independently arriving feedback,
missing acknowledgements, reconnect with cached values, and metadata removal.
Verify discovery and commands against the actual module model/firmware and
its retained MQTT control metadata before claiming hardware-tested support.

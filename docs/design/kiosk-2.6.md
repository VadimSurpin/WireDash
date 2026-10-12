# Kiosk: Wall display grows a lock (2.6)

Decided 2026-10-12 in a six-question round; the user took every
recommendation. Words follow [CONTEXT.md](../../CONTEXT.md) (**Wall
display**, **Kiosk lock**, **Edit lock**).

## Why

A tablet on the wall was the second-most asked thing after alerts, and the
asks were two: lock it so guests and children can't wander into Settings or
Edit, and go fullscreen. Wall display (signal-2.0.md §7) only kept the screen
on and hid the app's own bars. 2.6 makes it the one feature for a wall
tablet, with the lock, Android's bars gone, and dimming.

## Decisions

1. **One feature, not two.** The ⋮ menu's "Wall display" opens a sheet
   instead of toggling: Keep the screen on and hide the bars (today's
   behaviour, stored under the same key, so nobody who has it on notices a
   change), Fullscreen, Dim after, and the Kiosk lock with its PIN and
   Android screen pinning. The store and README say "kiosk mode"; the app
   keeps the name users know.
2. **The lock is an in-app PIN, optional.** Leaving kiosk is a long-press on
   the dashboard's title; with a PIN set, the long-press asks for it. Four
   digits, in the same encrypted store as broker passwords, one per device.
   Android screen pinning is an extra switch, off by default: on a tablet
   with no lock screen it unpins with a gesture alone, so it can't be the
   lock, but with one it also blocks Home and recent apps. A forgotten PIN
   has no bypass: the PIN dialog's "Forgot the PIN?" says that clearing
   ZigDash's data ends kiosk and loses the Home unless there is a backup,
   and the sheet offers Export backup before a PIN is set.
3. **What a guest can do.** Tiles, device sheets with their controls, and
   the other dashboards of the same Home. Nothing else: no Devices, Scenes,
   Settings, Edit mode, Home switching, alerts, device pages, the ⋮ menu,
   Add tile, or the consent, poll and community cards. A router redirect
   sends every other address back to the kiosk dashboards, so back presses,
   notification taps and widget deep links can't leave either; the system
   back button does nothing on the kiosk screen.
4. **Fullscreen** hides Android's status and navigation bars (a swipe from
   the edge shows them briefly, as everywhere on Android). Off until chosen;
   turning the Kiosk lock on sets it unless the user already chose.
5. **Dim after** 1, 5 or 15 minutes without a touch, or off; any touch
   restores the brightness. Off until chosen; the Kiosk lock sets 5 minutes
   unless the user already chose. Fullscreen and Dim apply while Wall display
   or kiosk is on. No clock or screensaver.
6. **Measured.** `feature_used` with feature `kiosk` when the lock is turned
   on, with `lock` (pin or none), `os_pin` (yes or no) and `dim` (off, 1m, 5m,
   15m). Both privacy policy copies list it.

Kiosk survives a restart: the pinned Home and dashboard are stored on the
device, and the router redirect runs on the first address too, so a tablet
that reboots comes back in kiosk. Android drops screen pinning on reboot;
ZigDash asks for it again when the kiosk dashboard opens.

## Code

- `lib/features/kiosk/kiosk.dart`: `KioskState`, `KioskController`
  (start, stop, PIN, OS pinning), `KioskPinStore`, `kioskRedirect`.
- `kiosk_pin_dialogs.dart`: set a PIN (twice), enter the PIN with Forgot.
- `wall_display_sheet.dart`: the sheet, `leaveKiosk`.
- `lib/features/dashboards/wall_display.dart`: `ScreenWake` gains
  `fullscreen`, `dim` and `lockTask` (seams; the last two through the
  `zigdash/app` channel, `setBrightness` and `lockTask` in MainActivity);
  `WallFullscreenSetting`, `WallDimSetting`; `WallDisplayScope` applies all
  of it.
- `dashboards_screen.dart`: the kiosk header (title to long-press, no
  actions), hidden cards and FAB, back swallowed; `_DashboardMenu` opens the
  sheet; the export dialog moved to `widgets/export_dialog.dart` so the sheet
  can offer it.
- `home_shell.dart`: no navigation in kiosk. `panel_grid.dart`: tiles lock
  their long-press. `device_sheet.dart`: no device page link.
- `app_router.dart`: `kioskRedirect` after the first-run redirect.
- Strings: `wallSheet*`, `wallKeepOn*`, `wallFullscreen*`, `wallDim*`,
  `kiosk*`, `a11yKioskLeave`; `dashFormLock` reads "Edit lock". 11 ARBs.
- Tests: `test/features/kiosk/kiosk_test.dart` (redirect, controller, PIN),
  `kiosk_screen_test.dart` (sheet, start, leave, PIN, OS pinning),
  `wall_display_test.dart` (fullscreen, dim, pinning through the scope).

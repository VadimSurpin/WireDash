# Android Auto state-refresh scrolling

The affected host is Android Auto 17.9. The user confirmed that fresh state
published from the phone resets the car dashboard to the top even without a car
tap. Sending feedback via native popups is useful, but does not fix this separate
state-refresh reset. No verified workaround for this host has been established.

## Public API limits

The previous grouped grid explicitly sets
[`SCROLL_STATE_PRESERVE_INDEX`](https://developer.android.com/reference/androidx/car/app/model/SectionedItemTemplate.Builder#setScrollStatePersistenceStrategy(int)).
That request applies when the host treats a template as a refresh. The API
offers reset-to-top or preserve-index strategies, without a target scroll index
or a `scrollToPosition()` command for this grid.

API 8 sections provide an
[item visibility callback](https://developer.android.com/reference/androidx/car/app/model/Section.BaseBuilder#setOnItemVisibilityChangedListener(androidx.car.app.model.ItemList.OnItemVisibilityChangedListener)).
WireDash now remembers each reported range (start inclusive, end exclusive).
This can show where a reset happened; it cannot force the host to scroll back.
The underlying scrollable view belongs to Android Auto, outside WireDash's UI.
`ItemList.setSelectedIndex()` configures selectable lists, not this grid's scroll
position. Back-navigation template IDs are not a supported scroll override.

Android `GridView.getFirstVisiblePosition()`, `setSelection(index)` and
`smoothScrollToPosition(index)` work on an app-owned
[`android.widget.GridView`](https://developer.android.com/reference/android/widget/GridView).
WireDash has no such view in its projected car UI: `SectionedItemTemplate` is a
data model rendered inside the separate Android Auto host. These methods cannot
be called on the template or its `GridSection`, and creating an unused local
`GridView` would not move the car's grid.

## Research

* Google's [issue 461256656](https://issuetracker.google.com/issues/461256656)
  changed the default policy to preserve index. WireDash already sets that
  policy explicitly, so the default change does not explain or solve this case.
* AndroidX Media [issue 2192](https://github.com/androidx/media/issues/2192)
  reports Android Auto content resetting on playback-state/progress updates,
  reproduced in the DHU and cars. Maintainers identify the companion host as
  responsible for that UI. Disabling periodic media-session position updates is
  a reported workaround for those apps. WireDash uses IoT templates, not a media
  session, so that switch does not apply here. This is related evidence, not
  confirmation that the same defect causes WireDash's reset on 17.9.

## Build 102 behavior and diagnostics

Connection loss uses one localized native popup per outage rather than replacing
every control caption. The grouped grid retains its last-known items while
offline; existing click delegates check current connectivity and reject commands.
Manual reconnect and offline taps show the reminder immediately. Actual MQTT
state still changes state icons after reconnection; state feedback is not frozen
to mask the scrolling issue.

Debug APKs log only section ordinals, item indices, changed-section counts and
connection/preservation flags under `WireDashAuto`. They do not log control names,
MQTT topics/payloads, credentials or video URLs. Capture with:

```sh
adb logcat -s WireDashAuto:D '*:S'
```

Scroll down, change a control from the phone, and compare the last `viewport`
range, the `refresh` entry and the next `viewport` range. Section indices are
zero-based. A reset can be correlated with the submitted update; a visibility
callback alone does not distinguish a user's own scroll from a host reset.

Regression tests simulate phone-origin state changes and visibility callbacks,
require one state refresh with preserve-index requested, and require no template
submissions for reconnect-only or command-progress feedback. They cannot assert
the real host's scroll position. Use the projected DHU or the affected car for
that check: the available Automotive OS emulator does not render this template
(see [verification](ANDROID_AUTO.md#verification)).

## Build 104 list experiment

The API 8 dashboard now tries a classic grouped
[`ListTemplate`](https://developer.android.com/reference/androidx/car/app/model/ListTemplate)
instead of the lazy grid. Saved group headings, row counts and control titles
remain stable during state updates; toggles and action icons reflect feedback.
Each shutter/gate has Open and Close together, using the
[two inline actions supported on API 8](https://developer.android.com/reference/androidx/car/app/model/Row.Builder#addAction(androidx.car.app.model.Action)).
Stop and additional presets occupy more rows. Larger dashboards page at the
host's list limit rather than silently dropping controls.

The list reuses unchanged rows, action delegates and item lists. Starting or
finishing a command and losing/recovering connectivity submit no template when
there is no actual appearance change. State changes still update the appropriate
row; they are not hidden to mask scrolling. Classic grouped lists reject item
visibility callbacks, so their viewport cannot be logged through that API.
There remains no public manual-scroll command for this template.

Tests cover grouped order, paired actions, native toggles, phone-origin state,
retained offline rows with guarded commands, complete pagination, saved presets,
removed/hidden actions and offline cameras. These are client-side checks. The
list's real scroll position must still be tested on the affected Android Auto
17.9 host before calling this a fix.

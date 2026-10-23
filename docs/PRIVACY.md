# WireDash privacy

WireDash has no telemetry SDK, usage tracking, automatic crash reporting, or
feature-request polls. It does not upload app activity to analytics services.
Legacy queued usage events from earlier builds are deleted on upgrade.

Connections, dashboards and settings are stored on your device. Passwords and
WireGuard configurations use encrypted device storage. MQTT, Home Assistant,
WireGuard, and optional alert/history services connect to the services you
configure as needed to provide their features. Direct MQTT needs no WireDash
server or cloud account.

Optional hub-side automation uses ZigDash Engine. Its installation requires an
explicit action and consent. Optional remote relay access uses the upstream
ZigDash relay service and encrypted home data; it is configured separately and
is not required for local MQTT or WireGuard. WireGuard connections never fall
back to the relay, including when a tunnel configuration is missing.

Help and problem reports are initiated by you. The bundled manual and support
details are shown locally. Report buttons open an editable GitHub issue draft
in VadimSurpin/WireDash; they do not submit reports. Review the details before
posting: GitHub issues are public. Copy details only writes to your clipboard.
Project, setup-guide, privacy and release links point to the WireDash repository
and open only after a tap. There is no inherited email contact, Telegram link
or automatic Play review request. External applications and GitHub use their
own privacy policies. Upstream links remain in the README for attribution.

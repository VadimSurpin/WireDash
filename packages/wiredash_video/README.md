# WireDash video plugin

A bundled Android dashboard extension for standard RTSP live streams and
Hikvision DVR/NVR recording playback. Native rendering uses media_kit/libmpv;
no Hik-Connect account, cloud relay, or proprietary Hikvision SDK is required.

## Add a camera

Open the dashboard's **Add tile → Custom MQTT tile → Video**. Video is independent
of MQTT: it does not need a topic, and remains usable if the MQTT broker is offline.
Use a Wide or Full tile for a useful video size.

For a standard camera, enter its `rtsp://host:port/path` URL. Port 554 is used when
omitted. Enter credentials in the video login fields. Pasted RTSP URL credentials
are moved to secure storage on Save and removed from the saved URL.

For a Hikvision recorder, enter its HTTP(S) base address and camera channel, and
leave RTSP URL blank. Channel 1 uses `/Streaming/Channels/102` for the live
substream and channel 17 uses `/Streaming/Channels/1702`. Disable substream for
main-stream live video. An explicit RTSP URL overrides this generated address,
including its port and stream path.

Tap Play to open the embedded video. Playback starts muted by default. The player
provides fullscreen and playback controls; Stop releases the player and route.
Going into the background stops playback and a returning user starts a fresh
connection explicitly. Cameras do not open automatically just because a dashboard
is loaded. Long-press and tile sizing use the existing dashboard controls.

## Saved recordings and presence

Enable **Hikvision recordings**, supplying the recorder address and an account
with remote playback/search permission. The history button opens a time-range
browser. Searches are limited to seven days per request, default to the previous
24 hours, and page through results with Load more. Displayed times use the phone's
local timezone; requests use UTC. Selecting a result plays that recording over RTSP.

Ordinary recording search uses `POST /ISAPI/ContentMgmt/search` and the returned
`playbackURI`. The main recording track is channel × 100 + 1. The exact file path
and query are retained while the host/port are replaced with the configured RTSP
endpoint, so LAN addresses returned by a remotely reached DVR do not escape the
configured route.

Human and vehicle filters use the recorder's own stored classification, through
`/ISAPI/ContentMgmt/SearchByTargetType?format=json`. The plugin checks its
capabilities endpoint and enables only advertised target types. This needs a
compatible recorder/firmware with human/vehicle detection and linked recording
already configured (for example, compatible AcuSense models). It does not infer
presence from ordinary motion, run phone-side AI, or change recording schedules.
If target search is unavailable, All recordings remains available. Recorders
using a different smart-search schema need an additional adapter; there is no
claim that every Hikvision model supports this endpoint.

## Credentials and network

Login data uses the host's encrypted secure storage, separately from panel JSON.
Exports contain a credential reference, not the password; a restored dashboard
on another phone needs the login entered there. Editing a duplicated panel's
login creates a new reference and preserves the original panel's login.

The default network option follows the dashboard home's route. HTTP(S) requests
use private WireGuard sockets when configured. RTSP media uses interleaved TCP
through a temporary loopback forwarder borrowing the same embedded tunnel;
failed tunnel creation has no direct fallback. RTSP over TCP is required for
this embedded route; encrypted RTSPS requires a system VPN/direct route instead.
Turn off the home-route option to use the phone's normal network/system VPN.
Trusted HTTPS certificates are verified normally.

The ISAPI client supports HTTP Digest MD5/SHA-256, including session algorithms,
nonce counts and stale-nonce challenges, plus server-challenged Basic. It does
not follow recorder redirects. Player failures show a generic message without
printing credential-bearing stream addresses.

## Packaging and validation

`wiredash_video` depends only on the small `wiredash_plugin_api` host contract.
Register it in `lib/plugins/panel_plugins.dart`; the core stores a generic
`PluginPanelConfig` envelope instead of camera-specific database fields. Removing
an extension from the registry leaves a placeholder and preserves saved settings.
The Android native video libraries are selected explicitly. Other platforms
need their corresponding native backend before enabling playback. Video is not
registered as an Android Auto control.

Tests under `test/plugins` exercise protocol fixtures, actual local HTTP challenge
exchanges, pagination, credentials, user/background lifecycle, MQTT-independent
dashboard rendering, and authenticated WireGuard forwarding. These are automated
fixture tests. A physical Hikvision DVR and native video decoding have not yet
been verified with this feature.

For a device test, start with one H.264 substream on the LAN, repeat via the home
WireGuard route, then search a known recording interval with All, People and
Vehicles. Confirm channel numbering, event configuration, playback permissions,
background cleanup and an interval containing more than 40 results.

Sources: [Hikvision live/recording integration guide](https://www.hikvisioneurope.com/eu/portal/portal/Technology%20Partner%20Program/03-How%20to/How%20to%20search%20and%20download%20the%20video%20file%20from%20NVR%20via%20ISAPI.pdf),
[Hikvision ISAPI developer guides](https://tpp.hikvision.com/download/),
[ISAPI target-search flow in ACTi's implementation guide](https://download.acti.com/?id=34491),
[target-search request/response example](https://github.com/Laudrice/Intelligent_Video_Monitoring_System/blob/aa96af74fe2d0daabc268641b9cca0d76953328b/backend/server.js#L669),
[media_kit](https://github.com/media-kit/media-kit), and
[Android native library source/builds and notices](https://github.com/media-kit/libmpv-android-video-build).

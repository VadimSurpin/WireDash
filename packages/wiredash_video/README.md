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

Tap Play to open the embedded video. Playback starts muted by default. Pinch the
picture to zoom from 1× to 8× and drag to inspect the enlarged image. Reset zoom
restores the original view. Playback, mute, fullscreen, history and event controls
stay outside the transformed picture. This is digital zoom/pan, not camera PTZ.
The same widget is used for live video, fullscreen and recording playback;
recordings expose a seek slider when the recorder reports a duration. Recording
playback always offers rewind/forward by 10 seconds and one minute, a recording
clock, and Return to selected event. These controls reopen playback by UTC time,
so they work with unknown-duration RTSP and can reach footage before the selected
event when it exists. They jump through footage; they do not claim reverse or
accelerated decoding support from every recorder. Expanding fullscreen preserves
the current recording time.
Stop releases the player and route.
Transient decoder errors clear once unbuffered playback advances again, including
when a reconnected stream restarts its playback clock.
Going into the background stops playback and a returning user starts a fresh
connection explicitly. Cameras do not open automatically just because a dashboard
is loaded. Long-press and tile sizing use the existing dashboard controls.

## Saved recordings and presence

Enable **Hikvision recordings**, supplying the recorder address and an account
with remote playback/search permission. The history button opens a time-range
browser with a vertical chronological timeline, grouped by local day. Each card
shows its time, duration, recorder event labels and a preview. The plugin first
checks for stored event-linked pictures on picture track channel × 100 + 3,
using the configured recorder's authenticated HTTP(S) connection and home route.
It prefers an explicitly classified person/vehicle capture when the recorder
returns one. The image caption shows its actual capture time; tapping the card
starts ordinary playback at that time, which can differ from the file start by
seconds or minutes because of pre-recording. Generic motion photos are labelled
Recorder event photo, not a verified person/vehicle crop. No target boxes or
classifications are invented. The full photo fits inside the preview, with a
bounded decode size for the timeline. Labels include continuous recording,
motion, alarm, intrusion,
line crossing, person and vehicle when reported by the recorder. Unknown types
remain labelled Recording; motion is not presented as a person or vehicle.
Tapping a preview opens the ordinary fullscreen viewer at the stored capture time
(or the recording start for a video-frame fallback) and continues along the track. Playback is not limited to the
six-second event clip or its returned file URI. Returning preserves the timeline
scroll position.

An actual detection photo requires saved event-linked picture capture and a
firmware-supported picture search endpoint. Human/vehicle video filtering alone
does not guarantee that pictures were saved. If no compatible event photo is
available, the fallback says **Video start · detection photo unavailable** and
uses the first recorded video frame. It does not estimate detection time from a
fixed delay or substitute the current live camera snapshot. Photo searches inspect
up to 40 stored captures in the recording interval, preferring matching target
classification; a capture outside those results needs a narrower time-range search
or a firmware-specific adapter. Camera model/firmware determines available data.

Preview frames are loaded lazily, one muted RTSP connection at a time, using the
same credentials and home route as playback. They use a short software decode
at 320-pixel output width, not the camera's current live picture. Frames are
captured through an app-private temporary JPEG that is removed after reading,
then cached locally; scrolling away cancels unneeded work. Each browser keeps
up to 48 frames / 8 MiB, with a shared 16 MiB memory cache and a private disk cache
limited to 64 MiB / 512 files. Frames expire after seven days and survive closing
the browser or restarting the app until Android clears its temporary storage.
Preview connections close before clip playback and while the app
is in the background. Failed captures show Load preview and never hide the clip.

Search results, selected ranges and recorder capabilities are cached privately
for up to one day. Reopening a recent timeline reuses its results and images
without another recorder search or decoder connection. Stored event-photo metadata
and JPEGs are cached separately from video-start frames. Missing photos are cached
briefly for recent recordings and up to one day for historical recordings; Refresh
checks again after enabling picture capture on the recorder. The rolling 24-hour range
refreshes after one minute; older results remain visible during updates or if a
request fails. A custom historical range stays fresh for one day. Refresh bypasses
the search/capability cache. Camera settings and credential references isolate
caches; cached recording URLs omit embedded login data.

Searches are limited to seven days per request, default to the previous
24 hours, and page through results with Load more. Displayed times use the phone's
local timezone; requests use UTC. Selecting a result plays that recording over RTSP.
The events button opens the same browser with the first advertised human/vehicle
filter selected. People and Vehicles can be switched within the browser. If the
recorder advertises neither, it explains the limitation and offers All recordings.

Ordinary recording search uses `POST /ISAPI/ContentMgmt/search`. Preview capture
uses the returned `playbackURI`, rewriting its host/port to the configured RTSP
endpoint so returned LAN addresses cannot escape the configured route. Viewer
playback instead uses `/Streaming/tracks/{channel × 100 + 1}?starttime=...` in UTC,
without `endtime`, file name or file size. Hikvision documents `endtime` as optional
for playback by time (general ISAPI guide, §15.9.17).

Search requests follow Hikvision's recorded-video example, with a fixed UTF-8
`Content-Length` and the all-recording descriptor `//recordType.meta.std-cgi.com`.
No `/All` suffix is used. HTTP failures include a short recorder `subStatusCode`
when available (such as `badXmlContent` or `noPermission`); raw error bodies,
stream addresses and logins are not displayed.

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
need their corresponding native backend before enabling playback.

## Android Auto

Camera panels appear in their saved dashboard groups on both modern and legacy
Auto hosts, including camera-only dashboards and when MQTT is offline. A camera
entry opens an explanation directing the user to the phone while parked. It never
sends an MQTT command or shares stream addresses/login references with the host.

The Android Auto IoT template cannot embed the Flutter video widget, receive
pinch/drag gestures, or display recording playback. This implementation therefore
does **not** provide video on the car display. Android Auto developer mode and
Unknown sources do not remove that host limitation. Google's current
[parked-app guide](https://developer.android.com/training/cars/parked/auto) lists
only games as supported on projected Auto; Android Automotive OS is a different
platform. Future parked-video hosts need a separate adapter before the same
zoomable widget can be offered there.

Tests under `test/plugins` exercise protocol fixtures, actual local HTTP challenge
exchanges, pagination, credentials, user/background lifecycle, MQTT-independent
dashboard rendering, and authenticated WireGuard forwarding. These are automated fixture tests. The `video-preview` workflow also runs an
Android emulator against an authenticated synthetic H.264 RTSP source and
asserts a rendered 320×180 video frame; its runtime evidence is uploaded as an
artifact. Stored detection-photo support and time navigation still need verification against
the target physical Hikvision model and firmware.

For a device test, start with one H.264 substream on the LAN, repeat via the home
WireGuard route, then search a known recording interval with All, People and
Vehicles. Confirm channel numbering, event configuration, playback permissions,
background cleanup and an interval containing more than 40 results.

Sources: [Hikvision live/recording integration guide](https://www.hikvisioneurope.com/eu/portal/portal/Technology%20Partner%20Program/03-How%20to/How%20to%20search%20and%20download%20the%20video%20file%20from%20NVR%20via%20ISAPI.pdf),
[Hikvision general ISAPI guide, recorded-video request example in §15.2.40](https://raw.githubusercontent.com/loozhengyuan/hikvision-sdk/master/resources/isapi.pdf),
[Hikvision ISAPI developer guides](https://tpp.hikvision.com/download/),
[ISAPI target-search flow in ACTi's implementation guide](https://download.acti.com/?id=34491),
[target-search request/response example](https://github.com/Laudrice/Intelligent_Video_Monitoring_System/blob/aa96af74fe2d0daabc268641b9cca0d76953328b/backend/server.js#L669),
[media_kit](https://github.com/media-kit/media-kit), and
[Android native library source/builds and notices](https://github.com/media-kit/libmpv-android-video-build).

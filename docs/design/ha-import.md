# Import from Home Assistant (design, open for decisions)

Started 2026-10-16 from a real-phone test on the user's Home Assistant home
(2.7.1): devices named only in Home Assistant reach ZigDash as
`0xa4c13836276df66f`, because Home Assistant keeps its names and rooms in
its own registry and never publishes them to MQTT. The user asked for "a
Home Assistant migration to ZigDash"; this is part **A** of it. Part **B**,
helping ZHA users move to Zigbee2MQTT, comes after and is sketched at the
end. Research behind it (HA core `dev` and Zigbee2MQTT `master` as of
2026-10-16, with file citations) is summarised in
[Facts](#facts-from-the-research).

**Status:** decided 2026-10-16: the user took every recommendation (Q1
Home Assistant's login page with a pasted token as the fallback, Q2 import
once with "Import again", Q3 a dashboard per floor with a section per room,
Q4 no layout copy, Q5 rename tiles only in existing homes, Q6 free, Q7 its
own release, 2.8, before the wall-tablet pack). Building on
`feat/ha-import`, in the build order below.

## Why

- Most people who reach ZigDash run Home Assistant: 270,000 of the 557,000
  installs that share their integrations use MQTT, and Zigbee2MQTT is the
  usual reason ([analytics.home-assistant.io](https://analytics.home-assistant.io/)).
- They have already named every device and put it in a room, in Home
  Assistant. ZigDash asks them to do it again, or shows addresses.
- Setup is where ZigDash loses people (every real session in the last two
  days ended there). A first dashboard that already looks like their home is
  the strongest answer to "why switch from Home Assistant's own app".

## What it does

The user signs in to Home Assistant once from ZigDash. ZigDash reads, and
never writes:

| From Home Assistant | Becomes in ZigDash |
|---|---|
| Device name the user gave (`name_by_user`) | Tile name (else ZigDash's own) |
| Device area, or an entity's own area when it overrides | Section (or dashboard, **Q3**) |
| Floors, if any | Dashboards (**Q3**) |
| The default dashboard's cards, if stored (**Q4**) | Tile order |

Matched by IEEE address: a Zigbee2MQTT device is
`identifiers: [["mqtt","zigbee2mqtt_0x…"]]` in Home Assistant's device
registry. Devices Home Assistant has but Zigbee2MQTT does not (Wi-Fi plugs,
ZHA devices, cameras) are left out and counted on the preview.

Not imported: automations, scripts, scenes that involve non-Zigbee2MQTT
devices, users, history. Home Assistant keeps running its automations; the
import screen says so in one line.

## The flow

1. **Where it starts.**
   - In setup, after connecting to the broker: when the scan saw Home
     Assistant (port 8123 answered), the review step gets "Import names and
     rooms from Home Assistant".
   - In Settings › Home: "Import from Home Assistant", for existing homes.
2. **Sign in.** Home Assistant's own login page opens in a browser tab
   (Custom Tab). The user signs in there; ZigDash never sees the password.
3. **Preview.** "23 devices in 6 rooms. 4 Home Assistant devices aren't in
   Zigbee2MQTT and are left out." Each room expands to its devices, with the
   Home Assistant name next to the Zigbee2MQTT address. Rooms can be
   unticked.
4. **Create.** Tiles, sections and dashboards are made the way setup makes
   them today (sizes by device class, climate preselected). For an existing
   home (**Q5**), tiles are renamed and nothing is moved unless asked.
5. **Done.** The sign-in is revoked (`/auth/revoke`) unless the user turned on
   keeping names in sync (**Q2**).

## Decisions for the user

**Q1. How the user signs in.**
- (a) **Home Assistant's login page** (OAuth). Needs a small page on a site
  ZigDash owns (GitHub Pages) that tells Home Assistant ZigDash's return
  link, `<link rel="redirect_uri" href="zigdash://auth">`. Home Assistant
  fetches that page itself during login, so a Home Assistant without
  internet access cannot sign in this way.
- (b) **A long-lived token** the user creates in their Home Assistant profile
  and pastes. Works offline; one more chore, and the token is good for 10
  years unless deleted.
- **Recommendation:** (a) first with (b) as the fallback link under it
  ("No internet on your Home Assistant? Paste a token instead").

**Q2. Import once, or keep names in sync.**
- Once: sign in, import, sign out. Nothing stored. Simplest and the most
  trustworthy story.
- Sync: keep the sign-in (encrypted on the phone, refreshed every 30
  minutes when used), and follow renames and room moves made in Home
  Assistant.
- **Recommendation:** once in the first version, with "Import again" in
  Settings. Sync later if people ask; it is the riskier promise.

**Q3. What Home Assistant's rooms become.** ZigDash has no rooms by design
([ADR 0001](../adr/0001-dashboards-not-rooms.md)): dashboards are the main
object and are split into sections. The ADR rejected rooms because
Zigbee2MQTT has no room data and assigning rooms by hand is a chore. Home
Assistant removes both reasons.
- (a) One dashboard, one **section per room**.
- (b) One **dashboard per room**.
- (c) One **dashboard per floor**, a section per room on it; (a) when there
  are no floors.
- **Recommendation:** (c). It keeps the ADR (still dashboards and sections,
  no room object) and fits big homes and wall tablets (one per floor).

**Q4. Copy Home Assistant's dashboard layout?** Many Home Assistant
dashboards are auto-generated (nothing stored) or built from custom cards
(Mushroom and others) ZigDash cannot map.
- **Recommendation:** not in the first version. Build from rooms. Revisit
  with real users' dashboards.

**Q5. Existing ZigDash homes.** Someone already using ZigDash imports later.
- **Recommendation:** rename tiles that still carry the device's own name
  (the same rule that follows renames today) and offer, separately, "Make a
  dashboard from your rooms". Never rearrange a dashboard the user built.

**Q6. Free.** Import is part of getting started; behind Pro it would cost
installs. **Recommendation:** free, always.

**Q7. When.** **Recommendation:** its own release (2.8) before the
wall-tablet pack (then 2.9), because it improves the first five minutes for
most new users, where ZigDash is losing them now.

## Technical defaults (change on request)

- **Transport:** one WebSocket session to `ws(s)://<ha>/api/websocket`,
  `auth` with the access token, then four reads, then close:
  `config/device_registry/list`, `config/area_registry/list`,
  `config/floor_registry/list` (missing on old Home Assistant: no floors),
  `config/entity_registry/list_for_display` (entity area overrides; skips
  disabled entities, short keys `ei`, `di`, `ai`).
- **Which Home Assistant:** the address the scan saw on 8123, or the one the
  user types; `https://` and Nabu Casa links work the same way. A
  self-signed certificate needs an explicit "trust this certificate" step.
- **Matching:** device `identifiers` contains `["mqtt",
  "zigbee2mqtt_<ieee>"]`, and the IEEE is in Zigbee2MQTT's `bridge/devices`
  (Home Assistant keeps removed devices). Skip `zigbee2mqtt_bridge_…` (the coordinator) and
  group identifiers (`zigbee2mqtt_<char codes>_<id>`, model `Group`). Child
  devices (`parent_device_id` set, Home Assistant 2026.9+) are skipped.
- **Names:** device `name_by_user`, else ZigDash's own name for the device (Home Assistant's `name` is only Zigbee2MQTT's). The import never uses entity
  names for tiles; a device tile shows the device.
- **Rooms:** device `area_id`; if all of a device's entities share another
  area, use that one.
- **Parsing is defensive:** `config_entry_id` or the older
  `config_entries`; unknown fields ignored; a failed `floor_registry` read is
  "no floors".
- **Login (Q1a):** `client_id` `https://<zigdash pages>/ha/`, PKCE S256
  (Home Assistant 2026.10+ checks it, older ones ignore it), redirect
  `zigdash://auth`. Code for tokens at `/auth/token`; revoke at
  `/auth/revoke` when done.
- **ZHA users:** devices with `["zha", …]` identifiers and none with
  `zigbee2mqtt_…` mean Zigbee2MQTT is not in use. The import says so and
  points to part B, instead of showing an empty preview.
- **Privacy:** reads names, rooms and floors of Zigbee2MQTT devices, on the
  phone only; nothing is sent anywhere but the user's Home Assistant. One
  analytics event, `ha_import`, with the outcome and counts in buckets (rooms,
  devices matched, devices left out). Policy updated with the release.
- **Permissions:** Home Assistant tokens have no scopes; any signed-in user
  (admin or not) can read the registries. The screen says ZigDash only
  reads, and (Q2 once) forgets the sign-in afterwards.

## Facts from the research

From Home Assistant core `dev` (2026.10.1 released) and Zigbee2MQTT
`master`, read 2026-10-16:

- Access tokens last 30 minutes; refresh tokens 90 days from last use;
  `/auth/revoke` ends both. `homeassistant://` return links are reserved for
  Home Assistant's own apps.
- `redirect_uri` must share the `client_id`'s host, or be declared on the
  `client_id` page with `<link rel="redirect_uri">` (Home Assistant fetches
  it, 5 s timeout), or in a client metadata document (2026.9+).
- No read-only tokens. Registry list commands need no admin rights.
- `lovelace/config` answers `config_not_found` for an auto-generated
  dashboard.
- Zigbee2MQTT publishes `identifiers: ["zigbee2mqtt_<ieee>"]`, and Home
  Assistant stores it as `("mqtt", …)`. It does not depend on base topic or
  discovery topic. No `connections` are sent.
- Registries come as one large JSON frame; big homes mean megabytes.

## Checked on a real Home Assistant (2026-10-16)

The user's Home Assistant 2026.1.1 on the Pi (Docker, Zigbee2MQTT through
MQTT, admin user), read through its own logged-in page:

- Zigbee2MQTT devices are `["mqtt","zigbee2mqtt_<ieee>"]` as researched;
  the bridge is `zigbee2mqtt_bridge_<ieee>`. `model` holds the description
  ("Motion sensor"), `model_id` the model (`ZG-204Z`). `connections` is
  empty. This version still sends `config_entries` (a list), not
  `config_entry_id`.
- **Home Assistant keeps devices Zigbee2MQTT no longer has.** A shutter
  removed from Zigbee2MQTT months ago is still in Home Assistant's registry
  with its old name. The import must take only devices that are in
  Zigbee2MQTT's own `bridge/devices` and ignore the rest (not count them as
  "left out", which would confuse).
- Floors work on 2026.1.1 (`config/floor_registry/list`).
- Area IDs are slugs of the first name, also for Hebrew names
  (`khdr_hvrym` for "חדר הורים"); show the area's `name`, never its ID.

**Test data set up, with the user's agreement** (to undo after testing):
floor "Ground floor" (`ground_floor`) holding Living Room and Kitchen;
`0xa4c13836276df66f` named "Living room motion" in Living Room;
`0xa4c13828d7b8e8a1` "Kitchen motion" in Kitchen; `0xa4c13863521bcd41`
"Bedroom motion" with no device area and all eight of its entities in
Bedroom (the entity-override case).

**Verified on the user's phone (2026-10-16, 12:52):** a test build of
`feat/ha-import` with a long-lived token the user created and pasted
themselves. Preview matched Home Assistant exactly (Ground floor: Kitchen,
Living Room; Other rooms: Bedroom from its entities; stale shutter left
out). Import: 3 tiles renamed on the setup dashboard, which stayed first,
and 2 dashboards added after it, with live readings.

## Testing

- Unit: matching, name and area rules, ZHA detection and the preview counts,
  against registry fixtures (small home, floors, overrides, groups, child
  devices, ZHA-only).
- Real: the user's Home Assistant on the Pi (`192.168.68.52:8123`, Docker,
  Zigbee2MQTT through MQTT, 3 motion sensors). Before building, give them
  names and two rooms in Home Assistant (the user agreed on 2026-10-16) and
  check the registry shapes above against it.
- Not testable at home: Home Assistant OS (add-ons, ingress), Nabu Casa,
  floors in a real home. A Home Assistant OS VM covers the first.

## Build order

1. Registry reader and matcher, pure, with fixtures (most of the risk).
2. Long-lived token path (Q1b) end to end, so import works before the login
   page exists.
3. Preview and create, in setup and Settings.
4. Home Assistant login (Q1a) and the GitHub Pages return page.
5. Analytics, privacy policy, 11 languages, goldens, phone test on the Pi.

## Part B, later: ZHA to Zigbee2MQTT

Home Assistant has 143,000 ZHA installs that ZigDash cannot serve today.
Moving them is the user's job, not ZigDash's; ZigDash can make it safe:

- **Recommend a second Zigbee adapter** running Zigbee2MQTT next to ZHA, and
  moving devices room by room (re-pair each). Nothing breaks at once and it
  can stop at any point. Moving a whole network without re-pairing works
  only for some adapters (`zstack`, `ember`) and is not something to
  promise.
- **Warn first:** each moved device gets new entity IDs in Home Assistant,
  so automations and dashboards that use it must be updated.
- **Track progress** with the same Home Assistant sign-in: "Kitchen: 3 of 5
  devices now in Zigbee2MQTT".
- Start with a guide page and the checks; build more only after real users
  try it.

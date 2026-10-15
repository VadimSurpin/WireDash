# Monetization options for ZigDash (research, 2026-10-15)

Deep-research run: 5 search angles, 21 sources fetched, 90 claims
extracted, 25 verified by three-vote adversarial review, 10 findings
survived, 9 refuted. Numbers are as of 2026-10-15.

## Where we stand

- About 190 installed devices, ~220 monthly active devices, ~12 new
  installs a day on Play (51% of store visitors install; most come from
  Play Explore and the search "zigbee2mqtt dashboard").
- Too few ratings for Play to show a rating.
- GitHub Sponsors live since 2026-10-09 on the README only, almost no
  sponsors. No link to it in the app (checked `lib/`, 2026-10-15), which
  is the right state (see finding 1).
- Listing promises: no cloud, no account, no ads. MIT licence. Also on
  IzzyOnDroid; F-Droid request pending.

## Recommendation (ranked)

1. **One-time "Pro / Supporter" unlock through Play Billing, about 7 to
   9 EUR, gating only new depth features.** This is what the two closest
   comparables do (IoT MQTT Panel Pro, Fully Kiosk PLUS), it keeps the
   free listing and the 51% install conversion intact, F-Droid policy
   allows it, and Play's fee is ~15% in every market we sell in.
   Realistic revenue at ~360 installs a month is tens to low hundreds of
   EUR a month (our arithmetic: 2 to 5% unlock rate at ~7 EUR net is
   40 to 110 EUR/month). So this is about putting the structure in place
   while the audience is small, not about income now.
2. **In-App Review prompt after a successful setup.** The only growth
   lever with documented uplift that fits our scale (Babbel: +64% rating
   volume). A visible rating also changes how the Play card looks (today
   it shows none).
3. **Keep GitHub Sponsors as goodwill, README and website only.** Never
   in the Play build. Yields at hobbyist scale are tiny.
4. **Not now:** subscription, paid cloud (conflicts with local-only and
   no comparable supports it), tip-jar SKU with nothing attached (no
   documented approval), paid listing like DAVx5 (ends the free funnel),
   SMLIGHT bundling (possible, weak), listing experiments (need ~10x the
   traffic).

### What the app needs for option 1

- Two product flavors: Play (Play Billing, one managed product) and
  F-Droid/GitHub (everything unlocked, or an off-Play activation code
  later). F-Droid strips the Play Billing SDK, so a Play-only unlock
  would leave that build with no payment path.
- Gates with precedent, all on top of the free core dashboard: wall
  tablet and kiosk depth (screensaver, motion wake, scheduled dimming,
  remote admin), alert or automation extras, supporter cosmetics (icon,
  theme). Nothing that exists today moves behind the gate.
- A Google Play payments profile (none exists yet) and enrollment in the
  15% tier for the legacy markets.
- Soft gate à la Fully Kiosk (feature works, watermark or nag) is an
  option; a hard gate is simpler to test.

## Findings

Confidence: high = 3-0 votes on primary sources; medium = 2-1 or
secondary sources; low = single self-reported source.

### 1. In-app links to GitHub Sponsors, Ko-fi, PayPal or Open Collective get open-source apps removed from Play (high)

Play's Payments policy, section 4: apps may not lead users to a payment
method other than Play's billing system, including through in-app
webviews, buttons, links and messaging. The donation exemption in
section 3 covers only tax-exempt recipients, not an individual
developer. Enforcement record: WireGuard removed October 2019 for a
browser link to its donations page; StreetComplete rejected 2022 for
GitHub Sponsors, Liberapay and Patreon links and even for a replacement
GitHub homepage link; AnkiDroid got a removal notice July to September
2026 over an Open Collective link, appeal unresolved. The only exceptions
are the US External Content Links program (live December 2025) and the
EEA external-offers program, both enrollment-only and regional; a global
link in an app with DE/US/BR/KR/CZ/EE/IL users stays a violation. Links
on the GitHub README or website are outside the policy.

Sources: Play Payments policy (support.google.com/googleplay/android-developer/answer/9858738);
WireGuard mailing list, October 2019 (lists.zx2c4.com/pipermail/wireguard/2019-October/004596.html);
Phoronix, "WireGuard is back on the Play Store"; StreetComplete issue 3768;
SufficientlySecure/donations README; Play External Content Links help
(answer/15582165).

### 2. Play's fee on a ZigDash purchase is about 15% in every market we sell in (high)

Since June 30 2026 the EEA, UK and US pay 10% service fee plus 5%
billing fee on the first $1M a year (Australia and Japan from September
30 2026, Korea by December 31 2026, rest of world by September 30 2027).
All remaining markets, including Israel, Brazil and Korea today, keep the
legacy tier: 15% to $1M, 30% above, flat 15% on subscriptions, which
needs enrollment in the Play Console. The fee follows the paying user's
region, not ours.

Sources: Play service fees (answer/112622); Play fee changes 2026 (answer/16954621).

### 3. The closest comparables sell a one-time unlock at 8 to 11 EUR, not a subscription (high)

IoT MQTT Panel sells a separate Pro listing at £8.49 / $9.49 (1k+
downloads against 100k+ for the ad-supported free app). Fully Kiosk
Browser sells PLUS at 8.90 EUR / 10.99 USD per device, one time,
lifetime; its cloud subscription is offered only to commercial users. A
German consumer pays about 10.59 EUR with VAT for Fully PLUS, so 9 to 11
EUR is the consumer anchor. Caveat: IoT MQTT Panel's free tier is
ad-funded, which our listing rules out, and a separate paid listing has
different implications from an in-app unlock.

Sources: Node-RED forum thread on MQTT dashboards (discourse.nodered.org/t/80823);
Play listing snr.lab.iotmqttpanel.prod.pro; fully-kiosk.com;
housecontrollers.de wall-panel guide (2026-07-13).

### 4. Kiosk depth and MQTT or Home Assistant remote control are already gated by the incumbent, with broad acceptance (high)

Fully Kiosk puts MQTT integration, remote administration, screensaver
and motion detection behind PLUS. The official Home Assistant
fully_kiosk integration says it requires the paid licence; the feature
works free with a watermark. This shows the market accepts gating these
features; Fully Kiosk is proprietary, so it says nothing about an
open-source community's reaction.

Sources: fully-kiosk.com feature list; home-assistant.io/integrations/fully_kiosk;
housecontrollers.de.

### 5. F-Droid allows pay-to-unlock, but its builds have no Play Billing, so a separate flavor is needed (medium, 2-1)

F-Droid contributors (hans, Licaon_Kter, 2018) said paid-to-unlock is
compatible with free software and F-Droid has no policy against
commercial activity; F-Droid will not patch out a feature gate against
the developer's wishes. The 2026 anti-features list has no pay-to-unlock
entry, and FairEmail is on F-Droid with pro features listed. F-Droid does
strip proprietary SDKs, so the F-Droid build has no Play Billing;
FairEmail works around it with web activation. The documented pattern is
two flavors: Play flavor with Play Billing only, F-Droid/GitHub flavor
unlocked or with an off-Play code. The SufficientlySecure/donations
library documents the split but is dead code (last push 2019).

Sources: forum.f-droid.org/t/paid-features-in-opensource-apps/4099;
F-Droid inclusion policy and anti-features docs; F-Droid FairEmail page;
SufficientlySecure/donations.

### 6. DAVx5's alternative: the same GPL app sold for a one-time fee on Play, free on F-Droid (high)

DAVx5 charges about $6.49 on Play, Huawei and Samsung stores and is free
on F-Droid and GitHub, justified by maintenance effort, with no
Play-only features. For ZigDash this ranks below an in-app unlock because
a paid listing ends the free install funnel that drives our growth (our
inference, not sourced).

Sources: davx5.com open-source info (updated 2026-08-25) and download
page; github.com/bitfireAT/davx5-ose.

### 7. External-link donations for free hobbyist apps yield almost nothing (low, single forum thread)

One Garmin Connect IQ developer: under $50 total on 130,000+ downloads.
Another in the same thread: about 100 EUR from 15 donations on ~2,500
downloads. At our scale either rate means single-digit donations. Treat
GitHub Sponsors as goodwill.

Source: forums.garmin.com developer thread 354118.

### 8. The In-App Review API is the one growth lever with documented uplift at our scale; listing experiments are not usable yet (medium)

Google's Babbel case study (about 2021): +64% rating volume and +0.11
stars in 19 days. It is a marketing case study on a tens-of-millions
install app with no control group, so take "rating volume rises", not
the percentage. Store listing experiments need thousands of visitors to
reach significance; at our ~24 visitors a day a 5-point conversion lift
would take about 103 days and a 2-point lift longer than Play's 6-month
auto-stop (verifier's arithmetic at 80% power, 90% confidence, 51%
baseline). Experiments become useful at roughly 10x the traffic.

Sources: Play Babbel case study; appdrift.co guide to listing
experiments; Play help on experiments (answer/6227309).

### 9. A SMLIGHT partnership is technically feasible but a weak lever (medium, 2-1)

SLZB-OS's standalone Zigbee Hub mode publishes device state and accepts
control over MQTT (plus an HTTP/SSE automation API), so ZigDash could
talk to SMLIGHT coordinators without Zigbee2MQTT. But it is limited to
TI CC26xx models (SLZB-06, 06p7, 06p10), is "still under development",
supports selected clusters only, and uses a zHub/HA-discovery topic
schema that would need its own adapter. No evidence surfaced on
Zigbee2MQTT sponsorship, installer or hospitality kiosk routes.

Sources: smlight.tech SLZB-OS page (v3.3.1); SLZB-06 manual, Zigbee Hub
mode.

### 10. A donation-style SKU through Play Billing has no documented rejection, and no documented approval (low)

All known enforcement actions concern external payment routes. The
SufficientlySecure/donations library kept a Play Billing donation flavor
after Google objected only to PayPal (2013). This is absence of evidence;
a supporter unlock that carries a feature is the safer framing than a
pure tip with nothing attached.

Sources: SufficientlySecure/donations; Play Payments policy.

## What did not survive verification

- Any revenue-per-active-user or unlock-conversion figure for smart-home
  or MQTT apps. Question 1 is unanswered; the 40 to 110 EUR/month
  estimate above is arithmetic, not data.
- Claims about how Play classifies a tip-jar IAP (two refuted 1-2).
- Claims that IoT MQTT Panel frames its Pro unlock as a tip, or about
  exactly which features it gates (refuted 0-3).
- That SMLIGHT's web UI makes a bundled dashboard redundant (0-3).
- That WireGuard permanently stripped its donation link (0-3).
- Any install uplift from the Home Assistant forum, Reddit, or a listing
  in the Zigbee2MQTT docs; no evidence either way.

## Open questions

- What unlock rate do indie Android utilities with a one-time Pro
  unlock see, and does a soft gate with watermark beat a hard gate for
  this audience?
- Does Play accept a supporter SKU with no feature attached for an
  individual developer?
- What do the community channels deliver in installs for a Zigbee2MQTT
  companion app?
- Any precedent for Zigbee2MQTT, SMLIGHT, Sonoff or installers
  sponsoring or bundling a third-party dashboard?

## Time-sensitive notes

Play fees are mid-rollout (dates above). The US External Content Links
program has been live only since December 2025 and needs enrollment. The
AnkiDroid appeal was unresolved as of September 2026. The "standard"
rates applying only above $1M is inferred from the fee table layout and
a Google blog post, not stated outright on the help page.

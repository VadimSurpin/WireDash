# SMLIGHT / SMHUB outreach (2026-10-16)

Replaces `posts.md` §5, which still says "no analytics" (wrong since ADR 0007: usage data is on by default and can be turned off).

Where SMHUB owners are, and why this order: SMLIGHT has no user forum and its Discord invite is dead. One share from SMLIGHT (blog, Telegram channel with ~1,900 subscribers, docs) reaches more owners than any forum reply, so email first, then two Home Assistant forum replies.

**Check before sending:** the lines in [brackets] are facts or choices only you can confirm. The forum replies are rough notes. The HA forum bans AI-written posts, so rewrite them in your own words.

---

## 1. Email to SMLIGHT

To: hello@smlight.tech

**Subject:** ZigDash — a free Android app for Zigbee2MQTT on SMHUB (mention or blog post?)

> Hello SMLIGHT team,
>
> I'm Gilad, an SMHUB Nano MG24 owner [two of them at home] and the author of ZigDash, a free, open-source (MIT) Android app that controls Zigbee2MQTT directly over MQTT. I built it around the SMHUB: the hub already runs Zigbee2MQTT, Mosquitto and Node-RED, so a phone app that talks straight to it covers a whole home with no server or Home Assistant needed.
>
> What it does for SMHUB owners:
>
> - **Setup that finds the hub.** It scans the network for the SMHUB's broker, and if the scan comes up empty, setup explains where to turn on the hub's MQTT broker settings.
> - **A dashboard that builds itself** from the devices Zigbee2MQTT reports: lights, shutters, plugs and sensors, plus history graphs for sensor readings.
> - **Automations that run on the hub, not the phone.** Schedules, auto-close rules and alerts (leak, smoke, door opened at night, low battery) run in the SMHUB's own Node-RED, which ZigDash sets up in one tap. They keep working with the phone off.
> - **Shortcuts:** home-screen widgets, Quick Settings tiles and Android Device Controls.
> - **A wall-tablet kiosk mode.**
> - **Remote access** over Tailscale, which runs on the hub.
>
> It has no ads and no account, and it's in 11 languages. It collects anonymous usage data that users can turn off; nothing about the home leaves the phone. [The core app stays free; an optional one-time supporter unlock for extra wall-tablet features is planned.]
>
> Would you consider either of these?
>
> 1. **A mention** of ZigDash as a phone app for SMHUB in your docs, knowledge base or Telegram channel.
> 2. **A short post for your blog**, like Mike Almeloo's remote-Zigbee post: how I run a home on an SMHUB with ZigDash, with screenshots. I'm happy to write it.
>
> And if there's anything you'd like changed or added for SMHUB users, I'm glad to do it. I'm already using your hardware daily [and found and worked around the EmberZNet 7.4.2 timeouts under bursts of reads before updating to 8.0.2].
>
> Play: https://play.google.com/store/apps/details?id=com.giladtamam.zigdash
> Source: https://github.com/giladtamam/zigdash
> Community: https://t.me/zigdash_app
>
> Best regards,
> Gilad Tamam

---

## 2. HA forum — "Smlight - smhub"

https://community.home-assistant.io/t/smlight-smhub/964193 (10 posts, last reply Oct 6). One reply asks whether anyone runs the hub with Zigbee2MQTT.

Notes to write from:

- Yes: Zigbee2MQTT on [two] SMHUB Nano MG24s, using the hub's own Mosquitto and Node-RED, [4 shutters and some lights].
- One useful tip from your own experience, so the reply helps even if no one cares about the app: [the coordinator ships with EmberZNet 7.4.2, which dropped off under bursts of reads; updating to 8.0.2 from Settings › Radios fixed it, but stop zigbee2mqtt first or the flash can stall in the bootloader].
- Disclose it's your app, in one line: "I wrote a free open-source Android app that talks to the hub's MQTT directly (no HA needed): ZigDash, [link]". Say why you built it.
- No feature list. Offer to answer questions.

Rough draft (rewrite):

> I run Zigbee2MQTT on two Nano MG24s, using the hub's own Mosquitto and Node-RED. One tip: mine shipped with EmberZNet 7.4.2 on the coordinator and it kept dropping out when lots of devices were read at once. Updating to 8.0.2 from Settings › Radios fixed it — stop zigbee2mqtt first, or the flash can get stuck in the bootloader.
>
> Since the hub runs everything locally, I wanted to control it from my phone without a server, so I wrote a free, open-source Android app for that: ZigDash (link). Happy to answer questions about running Z2M on the Nano.

---

## 3. HA forum — "SMHUB Nano MG24: Not just a Zigbee coordinator"

https://community.home-assistant.io/t/1028869 (Oct 14, 53 views, no replies yet). The author runs Zigbee2MQTT and Mosquitto on the Nano, with HA Core elsewhere, and likes that the hub works on its own.

Notes to write from:

- Agree with his point and add yours: the hub keeps the house running when HA or the server is down.
- What that looks like for you: [Node-RED on the hub runs schedules and alerts; the phone talks to the hub's Mosquitto directly].
- One line disclosing ZigDash is yours, as a way to use the hub on its own.
- Ask him something back (e.g. whether he bridges the Nano's broker to HA's or points HA at the Nano), so it reads as a conversation, not an ad.

Rough draft (rewrite):

> Same conclusion here. I treat the Nano as the place the house actually runs: Zigbee2MQTT, Mosquitto and Node-RED all on the hub, so schedules and alerts keep working when my server is down.
>
> For control without HA I wrote a free open-source Android app that talks to the Nano's broker directly — ZigDash (link). The hub-only setup is what made it possible.
>
> Do you point HA at the Nano's Mosquitto, or bridge it to your main broker?

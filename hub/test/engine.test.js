// Run: node --test hub/test/
'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const os = require('os');
const fs = require('fs');
const path = require('path');

process.env.ZIGBEE2MQTT_DATA = fs.mkdtempSync(path.join(os.tmpdir(), 'zigdash-engine-'));
const Engine = require('../zigdash-engine.js');
const H = Engine.helpers;

// ---------- a fake Zigbee2MQTT ----------

function fakeZ2m() {
  const listeners = { mqtt: [], entity: [], published: [] };
  const published = [];
  const injected = [];
  const devices = {
    '0xmotion': { name: 'Hallway motion', ieeeAddr: '0xmotion', isDevice: () => true },
    '0xlight': { name: 'Hallway light', ieeeAddr: '0xlight', isDevice: () => true },
    '0xbutton': { name: 'Bedroom button', ieeeAddr: '0xbutton', isDevice: () => true },
    '0xtemp': { name: 'Balcony', ieeeAddr: '0xtemp', isDevice: () => true },
    '0xdoor': { name: 'Front door', ieeeAddr: '0xdoor', isDevice: () => true },
  };
  const eventBus = {
    onMQTTMessage: (k, cb) => listeners.mqtt.push(cb),
    onPublishEntityState: (k, cb) => listeners.entity.push(cb),
    onMQTTMessagePublished: (k, cb) => listeners.published.push(cb),
    removeListeners: () => { listeners.mqtt = []; listeners.entity = []; listeners.published = []; },
  };
  const mqtt = {
    publish: (topic, payload, options) => { published.push({ topic: `${options.baseTopic}/${topic}`, payload, retain: options.clientOptions.retain, receive: options.skipReceive === false }); return Promise.resolve(); },
    subscribe: () => Promise.resolve(),
    unsubscribe: () => Promise.resolve(),
    onMessage: (topic, buf) => injected.push({ topic, payload: JSON.parse(buf.toString()) }),
  };
  const zigbee = { resolveEntity: (k) => devices[k] };
  const settings = { get: () => ({ mqtt: { base_topic: 'zigbee2mqtt' } }) };
  const logger = { info() {}, warning() {}, error() {}, debug() {} };
  const engine = new Engine(zigbee, mqtt, {}, null, eventBus, null, null, null, settings, logger);
  return {
    engine, published, injected, devices,
    rule: (id, rule) => listeners.mqtt.forEach((cb) => cb({ topic: `zigdash/automations/rules/${id}`, message: rule ? JSON.stringify({ v: 1, enabled: true, conditions: [], ...rule }) : '' })),
    meta: (m) => listeners.mqtt.forEach((cb) => cb({ topic: 'zigdash/automations/meta', message: JSON.stringify(m) })),
    control: (m) => listeners.mqtt.forEach((cb) => cb({ topic: 'zigdash/automations/control', message: JSON.stringify(m) })),
    mqttIn: (topic, message) => listeners.mqtt.forEach((cb) => cb({ topic, message })),
    z2mPublished: (topic, payload) => listeners.published.forEach((cb) => cb({ topic, payload: JSON.stringify(payload) })),
    at: (topic) => { const m = published.filter((p) => p.topic === topic).at(-1); return m && m.payload; },
    device: (ieee, message) => listeners.entity.forEach((cb) => cb({ entity: devices[ieee], message, payload: message })),
    last: (sub) => { const m = published.filter((p) => p.topic === `zigdash/automations/${sub}`).at(-1); return m && (m.payload ? JSON.parse(m.payload) : ''); },
  };
}

const lightOn = { type: 'device', commands: [{ ieee: '0xlight', payload: { state: 'ON' } }] };

// ---------- helpers ----------

test('hours windows, including across midnight', () => {
  assert.equal(H.withinHours('19:00', '18:00', '07:00'), true);
  assert.equal(H.withinHours('03:00', '18:00', '07:00'), true);
  assert.equal(H.withinHours('12:00', '18:00', '07:00'), false);
  assert.equal(H.withinHours('09:00', '08:00', '17:00'), true);
  assert.equal(H.withinHours('17:00', '08:00', '17:00'), false);
});

test('sunrise and sunset in Haifa on the solstice, within 3 minutes of published times', () => {
  // timeanddate.com, Haifa 2026-06-21: sunrise 05:31, sunset 19:49 (IDT, UTC+3)
  const meta = { lat: 32.794, lon: 34.989, timezone: 'Asia/Jerusalem' };
  const parts = { year: 2026, month: 6, day: 21 };
  const near = (hhmm, want) => Math.abs(H.toMinutes(hhmm) - H.toMinutes(want)) <= 3;
  const rise = H.triggerTime({ sun: 'sunrise', offset: 0 }, parts, meta);
  const set = H.triggerTime({ sun: 'sunset', offset: 0 }, parts, meta);
  assert.ok(near(rise, '05:31'), rise);
  assert.ok(near(set, '19:49'), set);
  assert.ok(near(H.triggerTime({ sun: 'sunset', offset: -30 }, parts, meta), '19:19'));
});

test('no sunrise in the polar night', () => {
  assert.equal(H.sunTimeUtc('sunrise', 2026, 12, 21, 78.2, 15.6), null);
});

test('rules the engine does not know are reported, not run', () => {
  assert.equal(H.validateRule({ v: 2 }), 'schema v2');
  assert.equal(H.validateRule({ v: 1, trigger: { type: 'geofence' }, action: lightOn }), 'unknown trigger');
  assert.equal(H.validateRule({ v: 1, trigger: { type: 'time' }, action: { type: 'device', commands: [] } }), 'no commands');
  assert.equal(H.validateRule({ v: 1, trigger: { type: 'time' }, conditions: [], action: lightOn }), null);
});

// ---------- the extension ----------

test('start publishes a retained state at the zigdash root', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  const s = z.published.find((p) => p.topic === 'zigdash/automations/state');
  assert.ok(s.retain);
  assert.equal(JSON.parse(s.payload).running_on, 'hub');
  await z.engine.stop();
  assert.equal(z.last('state'), '');
});

test('motion turns the hallway light on, once per change', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  z.rule('r1', { trigger: { type: 'device', ieee: '0xmotion', property: 'occupancy', equals: true }, action: lightOn });
  assert.equal(z.last('state').rules_loaded, 1);
  z.device('0xmotion', { occupancy: true });
  z.device('0xmotion', { occupancy: true, battery: 90 }); // repeat: no second run
  z.device('0xmotion', { occupancy: false });
  z.device('0xmotion', { occupancy: true });
  assert.deepEqual(z.injected.map((i) => i.topic), ['zigbee2mqtt/Hallway light/set', 'zigbee2mqtt/Hallway light/set']);
  assert.equal(z.last('recent').length, 2);
  await z.engine.stop();
});

test('a button fires on every press', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  z.rule('b', { trigger: { type: 'device', ieee: '0xbutton', property: 'action', equals: 'single' }, action: lightOn });
  z.device('0xbutton', { action: 'single' });
  z.device('0xbutton', { action: 'single' });
  z.device('0xbutton', { action: 'double' });
  assert.equal(z.injected.length, 2);
  await z.engine.stop();
});

test('a reading crossing a threshold fires once', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  z.rule('t', { trigger: { type: 'device', ieee: '0xtemp', property: 'temperature', above: 25 }, action: lightOn });
  z.device('0xtemp', { temperature: 24 });
  z.device('0xtemp', { temperature: 26 });
  z.device('0xtemp', { temperature: 27 });
  assert.equal(z.injected.length, 1);
  await z.engine.stop();
});

test('conditions: hours and another device', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  z.meta({ timezone: 'UTC' });
  z.engine.clock = () => new Date('2026-10-22T12:00:00Z');
  z.rule('c', {
    trigger: { type: 'device', ieee: '0xmotion', property: 'occupancy', equals: true },
    conditions: [{ type: 'hours', from: '18:00', to: '07:00' }],
    action: lightOn,
  });
  z.device('0xmotion', { occupancy: true });
  assert.equal(z.injected.length, 0, 'noon is outside 18:00-07:00');
  z.engine.clock = () => new Date('2026-10-22T22:00:00Z');
  z.device('0xmotion', { occupancy: false });
  z.device('0xmotion', { occupancy: true });
  assert.equal(z.injected.length, 1);

  z.rule('d', {
    trigger: { type: 'device', ieee: '0xbutton', property: 'action', equals: 'single' },
    conditions: [{ type: 'device', ieee: '0xdoor', property: 'contact', equals: true }],
    action: lightOn,
  });
  z.device('0xbutton', { action: 'single' });
  assert.equal(z.injected.length, 1, 'door state unknown');
  z.device('0xdoor', { contact: true });
  z.device('0xbutton', { action: 'single' });
  assert.equal(z.injected.length, 2);
  await z.engine.stop();
});

test('a clock-time trigger fires once on its minute, on its days only', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  z.meta({ timezone: 'Asia/Jerusalem' });
  z.rule('m', { trigger: { type: 'time', at: '06:30', days: [1, 2, 3, 4, 5] }, action: lightOn });
  // 2026-10-22 is a Thursday; 06:30 in Jerusalem (UTC+3) is 03:30 UTC
  z.engine.clock = () => new Date('2026-10-22T03:30:05Z');
  z.engine.onTick();
  z.engine.clock = () => new Date('2026-10-22T03:30:25Z');
  z.engine.onTick();
  assert.equal(z.injected.length, 1);
  z.engine.clock = () => new Date('2026-10-24T03:30:05Z'); // Saturday
  z.engine.onTick();
  assert.equal(z.injected.length, 1);
  await z.engine.stop();
});

test('turn off again after N minutes', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval'] });
  const z = fakeZ2m();
  await z.engine.start();
  z.rule('o', { trigger: { type: 'device', ieee: '0xmotion', property: 'occupancy', equals: true }, action: { ...lightOn, offAfter: 5 } });
  z.device('0xmotion', { occupancy: true });
  t.mock.timers.tick(5 * 60000);
  assert.deepEqual(z.injected.map((i) => i.payload.state), ['ON', 'OFF']);
  await z.engine.stop();
});

test('scene commands: by IEEE address, or a raw /set topic under the base only', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  z.rule('s', {
    trigger: { type: 'device', ieee: '0xbutton', property: 'action', equals: 'single' },
    action: { type: 'scene', commands: [
      { ieee: '0xlight', payload: { state: 'ON', brightness: 120 } },
      { topic: 'zigbee2mqtt/Old name/set', payload: { state: 'OFF' } },
      { topic: 'elsewhere/thing/set', payload: { state: 'ON' } },
    ] },
  });
  z.device('0xbutton', { action: 'single' });
  assert.deepEqual(z.injected.map((i) => i.topic), ['zigbee2mqtt/Hallway light/set', 'zigbee2mqtt/Old name/set']);
  assert.equal(z.last('recent')[0].commands, 2);
  await z.engine.stop();
});

test('a disabled or deleted rule does nothing', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  z.rule('x', { enabled: false, trigger: { type: 'device', ieee: '0xmotion', property: 'occupancy', equals: true }, action: lightOn });
  z.device('0xmotion', { occupancy: true });
  z.rule('y', { trigger: { type: 'device', ieee: '0xmotion', property: 'occupancy', equals: false }, action: lightOn });
  z.rule('y', null);
  z.device('0xmotion', { occupancy: false });
  assert.equal(z.injected.length, 0);
  assert.equal(z.last('state').rules_loaded, 1);
  await z.engine.stop();
});

test('unknown rules are listed in state', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  z.rule('future', { v: 2, trigger: { type: 'device' }, action: lightOn });
  assert.deepEqual(z.last('state').rules_unknown, ['future']);
  await z.engine.stop();
});

test('three errors in an hour stop the engine until the app starts it again', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  z.rule('r', { trigger: { type: 'device', ieee: '0xmotion', property: 'occupancy', equals: true }, action: lightOn });
  z.engine.zigbee.resolveEntity = () => { throw new Error('boom'); };
  for (const v of [true, false, true, false, true]) z.device('0xmotion', { occupancy: v }); // errors are caught
  assert.equal(z.last('state').stopped_self, true);
  assert.ok(fs.existsSync(path.join(process.env.ZIGBEE2MQTT_DATA, 'zigdash-engine-stopped')));
  z.engine.zigbee.resolveEntity = (k) => z.devices[k];
  z.device('0xmotion', { occupancy: false });
  z.device('0xmotion', { occupancy: true });
  assert.equal(z.injected.length, 0, 'stopped: no rules run');

  // the flag survives a restart
  await z.engine.stop();
  const z2 = fakeZ2m();
  await z2.engine.start();
  assert.equal(z2.last('state').stopped_self, true);
  z2.control({ cmd: 'start' });
  assert.equal(z2.last('state').stopped_self, false);
  assert.ok(!fs.existsSync(path.join(process.env.ZIGBEE2MQTT_DATA, 'zigdash-engine-stopped')));
  await z2.engine.stop();
});

test('a malformed rule payload is caught, not thrown into Zigbee2MQTT', async () => {
  const z = fakeZ2m();
  await z.engine.start();
  assert.doesNotThrow(() => z.engine.guard('x', z.engine.onMqtt)({ topic: 'zigdash/automations/rules/bad', message: '{not json' }));
  await z.engine.stop();
  fs.rmSync(path.join(process.env.ZIGBEE2MQTT_DATA, 'zigdash-engine-stopped'), { force: true });
});


// ---------- alerts and history flows ----------

const crypto = require('crypto');

function alertsConfig() {
  const vapid = crypto.generateKeyPairSync('ec', { namedCurve: 'prime256v1' });
  const jwk = vapid.publicKey.export({ format: 'jwk' });
  const phone = crypto.createECDH('prime256v1'); phone.generateKeys();
  return {
    home: 'Home', base: 'zigbee2mqtt', timeZone: 'UTC',
    vapid: {
      privateJwk: vapid.privateKey.export({ format: 'jwk' }),
      publicKey: Buffer.concat([Buffer.from([4]), Buffer.from(jwk.x, 'base64url'), Buffer.from(jwk.y, 'base64url')]).toString('base64url'),
    },
    phones: [{ id: 'p1', name: 'Phone', endpoint: 'https://fcm.googleapis.com/fcm/send/abc',
      p256dh: phone.getPublicKey().toString('base64url'), auth: crypto.randomBytes(16).toString('base64url') }],
    alerts: [{ id: 'a1', kind: 'leak', enabled: true, devices: [{ topic: 'zigbee2mqtt/Bathroom leak', ieee: '0xleak', name: 'Bathroom leak' }] }],
    text: { leak: '{name}: leak' },
  };
}

const flush = () => new Promise((r) => setImmediate(r));

test('alerts: with no Node-RED, the Engine takes over, sends a leak push and keeps Recent alerts', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'], now: 1_800_000_000_000 });
  const z = fakeZ2m();
  const calls = [];
  z.engine.fetch = async (url, init) => { calls.push({ url, init }); return { status: 201, text: async () => '' }; };
  await z.engine.start();
  z.mqttIn('zigdash/alerts/config', JSON.stringify(alertsConfig()));
  t.mock.timers.tick(46000); // the observe window passes with no foreign heartbeat
  assert.equal(z.last('state').flows.alerts, 'active');
  assert.equal(z.at('zigdash/alerts/bridge/state'), 'online');
  assert.ok(z.published.find((p) => p.topic === 'zigdash/alerts/bridge/state').receive, 'the beat must come back to tell Node-RED apart');

  z.z2mPublished('zigbee2mqtt/Bathroom leak', { water_leak: false });
  z.z2mPublished('zigbee2mqtt/Bathroom leak', { water_leak: true });
  await flush();
  assert.equal(calls.length, 1);
  assert.equal(calls[0].url, 'https://fcm.googleapis.com/fcm/send/abc');
  assert.equal(calls[0].init.headers['Content-Encoding'], 'aes128gcm');
  assert.equal(JSON.parse(z.at('zigdash/alerts/recent'))[0].kind, 'leak');
  await z.engine.stop();
  assert.equal(z.at('zigdash/alerts/bridge/state'), 'offline');
});

test('alerts: a Node-RED copy still beating keeps the Engine passive, then it takes over', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'], now: 1_800_000_000_000 });
  const z = fakeZ2m();
  const calls = [];
  z.engine.fetch = async (url) => { calls.push(url); return { status: 201, text: async () => '' }; };
  await z.engine.start();
  z.mqttIn('zigdash/alerts/config', JSON.stringify(alertsConfig()));
  z.mqttIn('zigdash/alerts/bridge/state', 'online'); // the retained copy on subscribe: ignored
  for (let i = 0; i < 4; i++) { t.mock.timers.tick(30000); z.mqttIn('zigdash/alerts/bridge/state', 'online'); }
  assert.equal(z.last('state').flows.alerts, 'passive');
  z.z2mPublished('zigbee2mqtt/Bathroom leak', { water_leak: false });
  z.z2mPublished('zigbee2mqtt/Bathroom leak', { water_leak: true });
  await flush();
  assert.equal(calls.length, 0, 'passive: Node-RED sends this one');
  assert.equal(z.at('zigdash/alerts/recent'), undefined);

  t.mock.timers.tick(95000); // Node-RED's beats stopped
  assert.equal(z.last('state').flows.alerts, 'active');
  z.z2mPublished('zigbee2mqtt/Bathroom leak', { water_leak: false });
  await flush();
  assert.equal(calls.length, 1, 'the all-clear is sent by the Engine now: memory was kept while passive');
  await z.engine.stop();
});

test('history: records a reading and publishes its day record when the slot closes', async (t) => {
  t.mock.timers.enable({ apis: ['setTimeout', 'setInterval', 'Date'], now: Date.UTC(2026, 9, 22, 12, 0, 30) });
  const z = fakeZ2m();
  await z.engine.start();
  z.mqttIn('zigdash/history/config', JSON.stringify({ v: 1, timeZone: 'UTC',
    readings: [{ topic: 'zigbee2mqtt/Balcony', ieee: '0xtemp', attr: 'temperature', path: 'temperature', unit: '°C' }] }));
  t.mock.timers.tick(46000);
  assert.equal(z.last('state').flows.history, 'active');
  z.z2mPublished('zigbee2mqtt/Balcony', { temperature: 21.5 });
  t.mock.timers.tick(16 * 60000);
  const day = z.published.filter((p) => p.topic === 'zigdash/history/0xtemp/temperature/2026-10-22');
  assert.ok(day.length >= 1, 'a day record was published');
  assert.ok(day.at(-1).retain);
  assert.deepEqual(JSON.parse(day.at(-1).payload).b[0], [48, 21.5, 21.5, 21.5]);
  await z.engine.stop();
});

test('hub/zigdash-engine.js is built from the current sources', () => {
  const r = require('child_process').spawnSync(process.execPath, [path.join(__dirname, '..', 'build.mjs'), '--check']);
  assert.equal(r.status, 0, String(r.stderr));
});

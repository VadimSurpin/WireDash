// Live check: the built Engine against a real Mosquitto 2.1 + dynamic security.
const path = require('path'), fs = require('fs'), os = require('os'), crypto = require('crypto');
const mqtt = require('mqtt');
const B = path.join(__dirname, '..', 'broker');
const pw = (n) => fs.readFileSync(path.join(B, n + '.pw'), 'utf8');
process.env.ZIGBEE2MQTT_DATA = fs.mkdtempSync(path.join(os.tmpdir(), 'zd-live-'));
const Engine = require(process.argv[2]);
const H = Engine.helpers;
const injected = [], listeners = { mqtt: [], entity: [], published: [] };
const devices = { '0xlamp': { name: 'Kitchen lamp', ieeeAddr: '0xlamp', isDevice: () => true } };
const engine = new Engine(
  { resolveEntity: (k) => devices[k] },
  { publish: () => Promise.resolve(), subscribe: () => Promise.resolve(), unsubscribe: () => Promise.resolve(),
    onMessage: (topic, buf) => injected.push({ topic, payload: buf.toString() }) },
  {}, null,
  { onMQTTMessage: (k, cb) => listeners.mqtt.push(cb), onPublishEntityState: (k, cb) => listeners.entity.push(cb),
    onMQTTMessagePublished: (k, cb) => listeners.published.push(cb), removeListeners: () => {} },
  null, null, null, { get: () => ({ mqtt: { base_topic: 'zigbee2mqtt' } }) },
  { info() {}, warning: (m) => console.log('WARN', m), error: (m) => console.log('ERR', m), debug() {} });
engine.mqttConnect = (url, options) => mqtt.connect(url, options);
const key = crypto.randomBytes(32);
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
const results = [];
const check = (name, ok) => { results.push(`${ok ? 'PASS' : 'FAIL'} ${name}`); };

(async () => {
  await engine.start();
  listeners.mqtt.forEach((cb) => cb({ topic: 'zigdash/remote/set', message: JSON.stringify({
    url: 'mqtt://127.0.0.1:18883', homeId: 'h1', username: 'hub-h1', password: pw('hub-h1'), key: key.toString('base64') }) }));
  await wait(800);
  check('hub connected to the relay', engine.remote && engine.remote.connected === true);

  const phone = mqtt.connect('mqtt://127.0.0.1:18883', { username: 'phone-h1', password: pw('phone-h1'), protocolVersion: 5, clientId: 'phone-h1-a' });
  const got = [];
  phone.on('message', (t, p) => got.push({ t, p }));
  await new Promise((r) => phone.on('connect', r));
  await phone.subscribeAsync(['homes/h1/s/#', 'homes/h1/hub']);
  listeners.published.forEach((cb) => cb({ topic: 'zigbee2mqtt/Kitchen lamp', payload: JSON.stringify({ state: 'ON' }) }));
  listeners.published.forEach((cb) => cb({ topic: 'zigbee2mqtt/bridge/devices', payload: '[]' }));
  await wait(500);
  const states = got.filter((m) => m.t.startsWith('homes/h1/s/'));
  check('phone gets the device state through the relay', states.length === 1);
  check('the relay only ever carried ciphertext and an opaque topic', states.every((m) => !m.t.includes('Kitchen') && !m.p.toString('latin1').includes('Kitchen')));
  const inside = states[0] && H.unseal(key, states[0].p);
  check('the phone unseals it with the home key', inside && inside.topic === 'zigbee2mqtt/Kitchen lamp' && JSON.parse(inside.payload).state === 'ON');
  check('hub presence is online', got.some((m) => m.t === 'homes/h1/hub' && m.p.toString() === 'online'));

  phone.publish('homes/h1/c', H.seal(key, { topic: 'zigbee2mqtt/Kitchen lamp/set', payload: { state: 'OFF' }, at: Date.now() }), { qos: 1 });
  await wait(500);
  check('a sealed command from the phone reaches Zigbee2MQTT once', injected.length === 1 && injected[0].topic === 'zigbee2mqtt/Kitchen lamp/set');

  const other = mqtt.connect('mqtt://127.0.0.1:18883', { username: 'phone-h2', password: pw('phone-h2'), protocolVersion: 5, clientId: 'phone-h2-a' });
  const leaked = [];
  other.on('message', (t) => leaked.push(t));
  await new Promise((r) => other.on('connect', r));
  const granted = await other.subscribeAsync('homes/h1/#').catch((e) => ({ error: e.message }));
  other.publish('homes/h1/c', Buffer.from('x'), { qos: 1 });
  await wait(500);
  check("another home's phone can't read home 1", leaked.length === 0);
  check("another home's phone gets a refused subscription", JSON.stringify(granted).includes('135') || JSON.stringify(granted).includes('128') || JSON.stringify(granted).includes('error'));

  const late = mqtt.connect('mqtt://127.0.0.1:18883', { username: 'phone-h1', password: pw('phone-h1'), protocolVersion: 5, clientId: 'phone-h1-b' });
  const lateGot = [];
  late.on('message', (t, p) => lateGot.push({ t, p }));
  await new Promise((r) => late.on('connect', r));
  await late.subscribeAsync('homes/h1/s/#');
  await wait(400);
  check('a phone connecting later gets the retained state at once', lateGot.length === 1);

  await engine.stop();
  await wait(600);
  check('hub presence turns offline when the Engine stops', got.filter((m) => m.t === 'homes/h1/hub').at(-1)?.p.toString() === 'offline');
  console.log(results.join('\n'));
  phone.end(); other.end(); late.end();
  setTimeout(() => process.exit(results.some((r) => r.startsWith('FAIL')) ? 1 : 0), 200);
})().catch((e) => { console.log('ERROR', e); process.exit(1); });

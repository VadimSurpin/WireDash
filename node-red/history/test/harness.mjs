// Runs the function-node bodies in node-red/history/*.js as Node-RED would,
// through a scripted day and midnight, and checks what gets published.
// Usage: node node-red/history/test/harness.mjs
import fs from 'node:fs';
import assert from 'node:assert/strict';
const dir = new URL('../', import.meta.url).pathname;
const load = name => new Function('msg', 'flow', 'env', 'node', 'Buffer', fs.readFileSync(dir + name + '.js', 'utf8'));
const fns = Object.fromEntries(['ingest', 'restore', 'record', 'tick', 'heartbeat'].map(n => [n, load(n)]));

let store = {};
const flow = { get: k => store[k], set: (k, v) => { store[k] = v; } };
const node = { warn: () => {}, error: () => {} };
const run = (name, msg = {}) => {
    const r = fns[name](msg, flow, { get: () => undefined }, node, Buffer);
    if (r === null || r === undefined) return [];
    if (Array.isArray(r)) return r.flat().filter(Boolean);
    return [r];
};
const TZ = 'Asia/Jerusalem';
const at = (dayOffset, h, m = 0) => { // a Date whose wall time in TZ is h:m on today+dayOffset
    const d = new RealDate(); const local = new RealDate(d.toLocaleString('en-US', { timeZone: TZ }));
    const diff = d - local; local.setHours(h, m, 0, 0); local.setDate(local.getDate() + dayOffset);
    return new RealDate(local.getTime() + diff);
};
const RealDate = Date;
const clock = t => { globalThis.Date = class extends RealDate { constructor(...a) { super(...(a.length ? a : [t])); } static now() { return t.getTime(); } }; };
const dateOf = t => new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(t);

let step = 0;
const check = (what, fn) => { step++; try { fn(); console.log(`ok ${step}: ${what}`); } catch (e) { console.log(`FAIL ${step}: ${what}\n   ${e.message}`); process.exitCode = 1; } };

const config = { v: 1, home: 'My Home', base: 'zigbee2mqtt', timeZone: TZ, keepDays: 30, readings: [
    { ieee: '0xa1', attr: 'temperature', topic: 'zigbee2mqtt/Living room', path: 'temperature', unit: '°C' },
    { ieee: '0xa1', attr: 'humidity', topic: 'zigbee2mqtt/Living room', path: 'humidity', unit: '%' },
    { ieee: '0xb2', attr: 'power', topic: 'zigbee2mqtt/Plug', path: 'power', unit: 'W' },
] };

// 1. Config.
run('ingest', { topic: 'zigdash/history/config', payload: JSON.stringify(config) });
check('config indexed by device topic', () => assert.deepEqual(Object.keys(store.index).sort(), ['zigbee2mqtt/Living room', 'zigbee2mqtt/Plug']));

// 2. First tick of the day: clears a week of records past the window, for every reading.
clock(at(0, 10, 0));
let out = run('tick');
const today = dateOf(at(0, 10)), yesterday = dateOf(at(-1, 10));
check('first tick clears records 30 to 36 days back, 7 per reading', () => {
    assert.equal(out.length, 21);
    assert.ok(out.every(m => m.retain && m.payload === ''));
    assert.ok(out.some(m => m.topic === `zigdash/history/0xa1/temperature/${dateOf(at(-30, 10))}`));
    assert.ok(!out.some(m => m.topic.endsWith(dateOf(at(-29, 10)))), 'day 29 back is kept');
});

// 3. Values in the 10:00 slot (slot 40): averaged, min, max.
for (const [t, temp] of [[1, 21.0], [5, 22.0], [9, 23.5]]) {
    clock(at(0, 10, t));
    run('record', { topic: 'zigbee2mqtt/Living room', payload: JSON.stringify({ temperature: temp, humidity: 50, battery: 90 }) });
}
clock(at(0, 10, 12));
check('nothing published while the slot is open', () => assert.equal(run('tick').length, 0));

// 4. Slot closes at 10:15: one record per reading with data.
clock(at(0, 10, 15));
out = run('tick');
check('closing a slot publishes the day records', () => {
    const t = out.find(m => m.topic === `zigdash/history/0xa1/temperature/${today}`);
    assert.ok(t && t.retain);
    assert.deepEqual(JSON.parse(t.payload), { v: 1, unit: '°C', b: [[40, 22.17, 21, 23.5]] });
    assert.ok(out.find(m => m.topic === `zigdash/history/0xa1/humidity/${today}`));
    assert.ok(!out.find(m => m.topic.startsWith('zigdash/history/0xb2/')), 'the plug sent nothing');
});
clock(at(0, 10, 16));
check('the same slot is not published twice', () => assert.equal(run('tick').length, 0));

// 5. Strings and junk: a numeric string counts, text and missing values do not.
clock(at(0, 10, 20));
run('record', { topic: 'zigbee2mqtt/Plug', payload: JSON.stringify({ power: '12.5' }) });
run('record', { topic: 'zigbee2mqtt/Plug', payload: JSON.stringify({ power: 'n/a' }) });
run('record', { topic: 'zigbee2mqtt/Plug', payload: 'not json' });
run('record', { topic: 'zigbee2mqtt/Other', payload: JSON.stringify({ power: 99 }) });
check('a numeric string is recorded, junk is ignored', () => assert.deepEqual(store.mem['0xb2/power'].slots[41], [1, 12.5, 12.5, 12.5]));

// 6. Restart: memory is gone; today's retained record comes back and refills it.
const saved = JSON.parse(out.find(m => m.topic === `zigdash/history/0xa1/temperature/${today}`).payload);
store = {};
run('ingest', { topic: 'zigdash/history/config', payload: JSON.stringify(config) });
clock(at(0, 11, 0));
run('restore', { topic: `zigdash/history/0xa1/temperature/${today}`, payload: JSON.stringify(saved) });
run('restore', { topic: `zigdash/history/0xa1/temperature/${yesterday}`, payload: JSON.stringify(saved) });
check('restore keeps today only', () => {
    assert.deepEqual(store.mem['0xa1/temperature'].slots[40], [1, 22.17, 21, 23.5]);
    assert.equal(store.mem['0xa1/temperature'].date, today);
});
run('record', { topic: 'zigbee2mqtt/Living room', payload: JSON.stringify({ temperature: 24 }) });
clock(at(0, 11, 15));
out = run('tick').filter(m => m.payload !== '');
check('after a restart the record holds old and new slots', () => {
    const t = JSON.parse(out.find(m => m.topic === `zigdash/history/0xa1/temperature/${today}`).payload);
    assert.deepEqual(t.b, [[40, 22.17, 21, 23.5], [44, 24, 24, 24]]);
});

// 7. An echo of our own record does not overwrite exact sums in memory.
run('record', { topic: 'zigbee2mqtt/Living room', payload: JSON.stringify({ temperature: 26 }) });
run('restore', { topic: `zigdash/history/0xa1/temperature/${today}`, payload: JSON.stringify({ v: 1, unit: '°C', b: [[45, 1, 1, 1]] }) });
check('memory wins over a record for the same slot', () => assert.deepEqual(store.mem['0xa1/temperature'].slots[45], [1, 26, 26, 26]));

// 8. Midnight: a value at 23:50, then the first tick after midnight publishes
// the full old day (its last slot included) and starts a new one.
clock(at(0, 23, 50));
run('record', { topic: 'zigbee2mqtt/Living room', payload: JSON.stringify({ temperature: 19 }) });
clock(at(1, 0, 1));
out = run('tick');
check('after midnight the old day is published in full', () => {
    const t = JSON.parse(out.find(m => m.topic === `zigdash/history/0xa1/temperature/${today}`).payload);
    assert.deepEqual(t.b.at(-1), [95, 19, 19, 19]);
    assert.equal(store.mem['0xa1/temperature'].date, dateOf(at(1, 0, 1)));
    assert.ok(out.some(m => m.payload === '' && m.topic.endsWith(dateOf(at(-29, 10)))), 'the day that left the window is cleared');
});

// 9. A value after midnight before any tick: the old day is not lost.
clock(at(1, 23, 59));
run('record', { topic: 'zigbee2mqtt/Plug', payload: JSON.stringify({ power: 30 }) });
clock(at(2, 0, 0, 30));
run('record', { topic: 'zigbee2mqtt/Plug', payload: JSON.stringify({ power: 40 }) });
out = run('tick');
check('a day closed by a new value is still published in full', () => {
    const t = JSON.parse(out.find(m => m.topic === `zigdash/history/0xb2/power/${dateOf(at(1, 12))}`).payload);
    assert.deepEqual(t.b.at(-1), [95, 30, 30, 30]);
});

// 10. Config off: nothing recorded any more.
run('ingest', { topic: 'zigdash/history/config', payload: '' });
run('record', { topic: 'zigbee2mqtt/Plug', payload: JSON.stringify({ power: 50 }) });
check('an empty config stops recording', () => assert.equal(store.cfg, null));
check('heartbeat is retained online', () => assert.deepEqual(run('heartbeat'), [{ topic: 'zigdash/history/bridge/state', payload: 'online', retain: true }]));
globalThis.Date = RealDate;

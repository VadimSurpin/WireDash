// Function node "ingest config". In: retained zigdash/history/config.
// Keeps the config and an index from device state topic to the readings
// recorded from it. An empty payload stops recording; records already on
// the broker stay until they age out.
const raw = msg.payload;
const empty = raw === undefined || raw === null ||
    (typeof raw === 'string' && raw.trim() === '') ||
    (Buffer.isBuffer(raw) && raw.length === 0);
if (empty) {
    flow.set('cfg', null);
    flow.set('index', {});
    return null;
}
const cfg = (typeof raw === 'object' && !Buffer.isBuffer(raw)) ? raw : JSON.parse(raw.toString());
const index = {};
const keys = new Set();
for (const r of (cfg.readings || []).slice(0, 50)) {
    if (!r.topic || !r.ieee || !r.attr || !r.path) continue;
    const key = r.ieee + '/' + r.attr;
    keys.add(key);
    (index[r.topic] = index[r.topic] || []).push({ key, path: r.path, unit: r.unit || '' });
}
flow.set('cfg', cfg);
flow.set('index', index);
// Forget readings that are no longer recorded.
const mem = flow.get('mem') || {};
for (const k of Object.keys(mem)) if (!keys.has(k)) delete mem[k];
flow.set('mem', mem);
return null;

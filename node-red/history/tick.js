// Function node "tick", every minute. Publishes each reading's day record
// when a 15-minute slot closes, publishes yesterday's final record after
// midnight, and on a new day clears records older than keepDays.
const cfg = flow.get('cfg');
if (!cfg) return null;
const tz = cfg.timeZone || 'UTC';
const keep = cfg.keepDays || 30;
const fmt = d => {
    const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
        .formatToParts(d).map(x => [x.type, x.value]));
    return { date: `${p.year}-${p.month}-${p.day}`, slot: Math.floor((Number(p.hour) * 60 + Number(p.minute)) / 15) };
};
const now = new Date();
const { date, slot } = fmt(now);
const round = x => Math.round(x * 100) / 100;
const record = (key, m, upTo) => {
    const b = Object.keys(m.slots).map(Number).filter(s => s < upTo).sort((a, c) => a - c)
        .map(s => { const [n, sum, min, max] = m.slots[s]; return [s, round(sum / n), round(min), round(max)]; });
    return { topic: `zigdash/history/${key}/${m.date}`, retain: true, payload: JSON.stringify({ v: 1, unit: m.unit || '', b }) };
};
const out = [];
const mem = flow.get('mem') || {};
// Days that "record" closed early.
for (const d of flow.get('done') || []) out.push(record(d.key, d.rec, 96));
flow.set('done', []);
for (const key of Object.keys(mem)) {
    const m = mem[key];
    if (m.date !== date) { // the day ended with no new value since
        out.push(record(key, m, 96));
        mem[key] = { date, slots: {}, pub: -1, unit: m.unit };
        continue;
    }
    if (m.pub !== slot && Object.keys(m.slots).some(s => Number(s) < slot)) {
        out.push(record(key, m, slot));
        m.pub = slot;
    }
}
flow.set('mem', mem);
// A new day (or the first tick after a start): clear old records. A week
// of dates beyond the window, so a recorder that was off for days still
// cleans up.
if (flow.get('day') !== date) {
    flow.set('day', date);
    const index = flow.get('index') || {};
    const keys = new Set();
    for (const rs of Object.values(index)) for (const r of rs) keys.add(r.key);
    for (let back = keep; back < keep + 7; back++) {
        const old = fmt(new Date(now.getTime() - back * 86400000)).date;
        for (const key of keys) out.push({ topic: `zigdash/history/${key}/${old}`, retain: true, payload: '' });
    }
}
return out.length ? [out] : null;

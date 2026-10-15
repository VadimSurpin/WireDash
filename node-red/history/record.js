// Function node "record". In: <base>/# device state messages.
// Folds each configured reading's value into its 15-minute slot of today
// (count, sum, min, max). Publishing happens in "tick".
const index = flow.get('index') || {};
const readings = index[msg.topic];
if (!readings) return null;
let state = msg.payload;
if (Buffer.isBuffer(state)) state = state.toString();
if (typeof state === 'string') { try { state = JSON.parse(state); } catch (e) { return null; } }
if (!state || typeof state !== 'object') return null;
const cfg = flow.get('cfg') || {};
const tz = cfg.timeZone || 'UTC';
const now = new Date();
const p = Object.fromEntries(new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' })
    .formatToParts(now).map(x => [x.type, x.value]));
const date = `${p.year}-${p.month}-${p.day}`;
const slot = Math.floor((Number(p.hour) * 60 + Number(p.minute)) / 15);
const mem = flow.get('mem') || {};
for (const r of readings) {
    let v = state;
    for (const seg of r.path.split('.')) v = v === null || v === undefined ? undefined : v[seg];
    if (typeof v === 'string' && v.trim() !== '') v = Number(v);
    if (typeof v !== 'number' || !isFinite(v)) continue;
    let m = mem[r.key];
    if (!m || m.date !== date) {
        // A new day before "tick" closed the old one: tick publishes the
        // old day from "done" so the last slots are not lost.
        if (m && m.date !== date) {
            const done = flow.get('done') || [];
            done.push({ key: r.key, rec: m });
            flow.set('done', done);
        }
        m = { date, slots: {}, pub: -1, unit: r.unit };
        mem[r.key] = m;
    }
    m.unit = r.unit;
    const s = m.slots[slot];
    m.slots[slot] = s ? [s[0] + 1, s[1] + v, Math.min(s[2], v), Math.max(s[3], v)] : [1, v, v, v];
}
flow.set('mem', mem);
return null;

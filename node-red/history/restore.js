// Function node "restore today". In: retained zigdash/history/+/+/+ (day
// records, read back on connect and echoed after each publish).
// Node-RED's context on the hub is memory-only, so after a restart today's
// record is the only copy of today's slots. Slots already in memory win:
// the record holds averages, memory holds the exact sums.
const parts = msg.topic.split('/'); // zigdash history <ieee> <attr> <date>
if (parts.length !== 5) return null;
const key = parts[2] + '/' + parts[3];
const date = parts[4];
const cfg = flow.get('cfg');
const tz = (cfg && cfg.timeZone) || 'UTC';
const now = new Date();
const today = new Intl.DateTimeFormat('en-CA', { timeZone: tz, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now);
if (date !== today) return null;
const raw = msg.payload;
if (raw === undefined || raw === null || raw === '' || (Buffer.isBuffer(raw) && raw.length === 0)) return null;
let rec;
try { rec = (typeof raw === 'object' && !Buffer.isBuffer(raw)) ? raw : JSON.parse(raw.toString()); } catch (e) { return null; }
const mem = flow.get('mem') || {};
const m = mem[key] && mem[key].date === date ? mem[key] : { date, slots: {}, pub: -1, unit: rec.unit || '' };
for (const b of rec.b || []) {
    const [slot, avg, min, max] = b;
    if (m.slots[slot]) continue;
    m.slots[slot] = [1, avg, min, max];
}
mem[key] = m;
flow.set('mem', mem);
return null;

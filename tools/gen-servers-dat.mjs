// Write a Minecraft multiplayer servers.dat (uncompressed NBT).
// Verified against the real file in the Prism `fabric` instance, which is
// plain NBT with no gzip wrapper.
import fs from 'node:fs';

const TAG_END = 0x00, TAG_BYTE = 0x01, TAG_STRING = 0x08, TAG_LIST = 0x09, TAG_COMPOUND = 0x0a;

const u8 = n => Buffer.from([n]);
const u16 = n => { const b = Buffer.alloc(2); b.writeUInt16BE(n); return b; };
const i32 = n => { const b = Buffer.alloc(4); b.writeInt32BE(n); return b; };
const str = s => { const b = Buffer.from(s, 'utf8'); return Buffer.concat([u16(b.length), b]); };

const named = (type, name, payload) => Buffer.concat([u8(type), str(name), payload]);

function serverEntry({ name, ip }) {
  return Buffer.concat([
    named(TAG_STRING, 'name', str(name)),
    named(TAG_STRING, 'ip', str(ip)),
    named(TAG_BYTE, 'hidden', u8(0)),
    u8(TAG_END),
  ]);
}

function serversDat(servers) {
  const entries = servers.map(serverEntry);
  const list = Buffer.concat([u8(TAG_COMPOUND), i32(entries.length), ...entries]);
  return Buffer.concat([
    u8(TAG_COMPOUND), str(''),          // root compound, empty name
    named(TAG_LIST, 'servers', list),
    u8(TAG_END),                        // end of root
  ]);
}

const out = process.argv[2];
fs.writeFileSync(out, serversDat([{ name: 'Gleamveil', ip: 'gleamveil.duckdns.org' }]));
console.log(`wrote ${out} (${fs.statSync(out).size} bytes)`);

// Pack an extension folder into plugin.zip (plugin.json, icon.png, src/ at the zip root).
// Minimal zip writer on Node's zlib: no dependency, works on Windows too.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

function files(dir, base = dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).flatMap((e) => {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) return files(p, base);
    return e.name === 'plugin.zip' ? [] : [path.relative(base, p).split(path.sep).join('/')];
  });
}

function pack(dir) {
  const local = [], central = [];
  let offset = 0;
  for (const name of files(dir).sort()) {
    const data = fs.readFileSync(path.join(dir, name));
    const comp = zlib.deflateRawSync(data);
    const crc = zlib.crc32(data);
    const n = Buffer.from(name);
    // 0x0800 = UTF-8 names; time/date fixed at 1980-01-01 so the zip is reproducible.
    const head = (sig, extra) => {
      const b = Buffer.alloc(extra ? 46 : 30);
      b.writeUInt32LE(sig, 0);
      let o = 4;
      if (extra) b.writeUInt16LE(20, o), o += 2; // version made by
      b.writeUInt16LE(20, o); b.writeUInt16LE(0x0800, o + 2); b.writeUInt16LE(8, o + 4);
      b.writeUInt16LE(0, o + 6); b.writeUInt16LE(0x21, o + 8);
      b.writeUInt32LE(crc, o + 10); b.writeUInt32LE(comp.length, o + 14); b.writeUInt32LE(data.length, o + 18);
      b.writeUInt16LE(n.length, o + 22);
      if (extra) b.writeUInt32LE(offset, 42);
      return b;
    };
    central.push(head(0x02014b50, true), n);
    const l = Buffer.concat([head(0x04034b50, false), n, comp]);
    local.push(l);
    offset += l.length;
  }
  const cd = Buffer.concat(central);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(local.length, 8); end.writeUInt16LE(local.length, 10);
  end.writeUInt32LE(cd.length, 12); end.writeUInt32LE(offset, 16);
  const out = path.join(dir, 'plugin.zip');
  fs.writeFileSync(out, Buffer.concat([...local, cd, end]));
  return out;
}

module.exports = { pack };

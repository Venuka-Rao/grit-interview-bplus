const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const root = process.cwd();
const bundlePath = path.join(root, '.grit-bplus-source.json.gz.b64');

if (!fs.existsSync(bundlePath)) {
  throw new Error('Source bundle is missing: ' + bundlePath);
}

const encoded = fs.readFileSync(bundlePath, 'utf8').replace(/\s+/g, '');
const json = zlib.gunzipSync(Buffer.from(encoded, 'base64')).toString('utf8');
const files = JSON.parse(json);

let restored = 0;
for (const [relativePath, contents] of Object.entries(files)) {
  const destination = path.resolve(root, relativePath);
  if (destination !== root && !destination.startsWith(root + path.sep)) {
    throw new Error('Refusing to restore a path outside the project: ' + relativePath);
  }
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, contents, 'utf8');
  restored += 1;
}

console.log('Restored ' + restored + ' B+ project files from the source bundle.');

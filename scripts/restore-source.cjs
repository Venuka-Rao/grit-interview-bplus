const fs = require('node:fs');
const path = require('node:path');
const zlib = require('node:zlib');

const root = process.cwd();
const partPaths = Array.from({ length: 6 }, (_, index) =>
  path.join(root, 'source-parts', 'part-' + String(index + 1).padStart(2, '0') + '.txt')
);

const parts = partPaths.map((partPath) => {
  if (!fs.existsSync(partPath)) {
    throw new Error('Source bundle part is missing: ' + path.relative(root, partPath));
  }
  return fs.readFileSync(partPath, 'utf8').replace(/\s+/g, '');
});
const encoded = parts.join('');

if (!/^[A-Za-z0-9+/]+={0,2}$/.test(encoded)) {
  throw new Error('The source bundle contains invalid base64 characters.');
}

let files;
try {
  const json = zlib.gunzipSync(Buffer.from(encoded, 'base64')).toString('utf8');
  files = JSON.parse(json);
} catch (error) {
  throw new Error('Could not decode the B+ source bundle: ' + error.message);
}

let restored = 0;
for (const [relativePath, contents] of Object.entries(files)) {
  const destination = path.resolve(root, relativePath);
  if (destination !== root && !destination.startsWith(root + path.sep)) {
    throw new Error('Refusing to restore a path outside the project: ' + relativePath);
  }
  if (typeof contents !== 'string') {
    throw new Error('Invalid source content for: ' + relativePath);
  }
  fs.mkdirSync(path.dirname(destination), { recursive: true });
  fs.writeFileSync(destination, contents, 'utf8');
  restored += 1;
}

console.log('Restored ' + restored + ' B+ project files from 6 source bundle parts.');

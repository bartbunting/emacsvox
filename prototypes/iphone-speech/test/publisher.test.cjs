// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

test('only the local publisher selects the Expo project for a staged app', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'iphone-publisher-'));
  t.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const manifest = path.join(root, 'app.json');
  const pristine = require.resolve('../app.json');
  function stage() {
    fs.copyFileSync(pristine, manifest);
    execFileSync(process.execPath, [require.resolve('../app.config'), manifest],
      {env: {...process.env, XDG_CONFIG_HOME: root}});
    return JSON.parse(fs.readFileSync(manifest, 'utf8')).expo;
  }
  const original = stage();
  assert.equal(original.owner, undefined);
  assert.equal(original.extra?.eas?.projectId, undefined);
  const projectId = '00000000-0000-4000-8000-000000000001';
  fs.mkdirSync(path.join(root, 'emacsvox'));
  fs.writeFileSync(path.join(root, 'emacsvox', 'iphone-expo.json'),
    JSON.stringify({owner: 'example-publisher', projectId, unrelated: 'local-only'}));
  assert.deepEqual(stage(), {...original, owner: 'example-publisher', extra: {eas: {projectId}}});
});

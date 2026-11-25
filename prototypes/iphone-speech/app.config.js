// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

// Keep the publisher's Expo project outside the checkout. A staged build
// embeds only the owner and project ID in its regular Expo manifest.
function appConfig({config}) {
  const directory = process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config');
  const file = path.join(directory, 'emacsvox', 'iphone-expo.json');
  if (!fs.existsSync(file)) return config;
  const {owner, projectId} = JSON.parse(fs.readFileSync(file, 'utf8'));
  if (typeof owner !== 'string' || !owner.trim() ||
      typeof projectId !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(projectId)) {
    throw new Error('Set owner and projectId in ' + file);
  }
  return {...config, owner, extra: {...config.extra, eas: {...config.extra?.eas, projectId}}};
}

module.exports = appConfig;

if (require.main === module) {
  const manifest = process.argv[2];
  const app = JSON.parse(fs.readFileSync(manifest, 'utf8'));
  app.expo = appConfig({config: app.expo});
  fs.writeFileSync(manifest, JSON.stringify(app, null, 2) + '\n');
}

// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
// Xcode's first-use prompt cannot be answered on a hosted build machine.
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const directory = path.join(os.homedir(), 'Library/org.swift.swiftpm/security');
const file = path.join(directory, 'plugins.json');
const plugin = {packageIdentity: 'swiftterm', targetName: 'SwiftTermBuildInfoPlugin',
  fingerprint: '464df5207fc2432e16c9a23abe538187196daf5f'};
fs.mkdirSync(directory, {recursive: true});
const existing = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, 'utf8')) : [];
if (!existing.some(p => p.packageIdentity === plugin.packageIdentity &&
    p.targetName === plugin.targetName && p.fingerprint === plugin.fingerprint)) {
  fs.writeFileSync(file, JSON.stringify([...existing, plugin], null, 2));
}

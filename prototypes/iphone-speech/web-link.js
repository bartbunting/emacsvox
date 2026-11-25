// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later
function isWebLink(text) {
  if (typeof text !== 'string' || text.length > 8192 || !/^https?:\/\//i.test(text) ||
      /[\x00-\x20\x7f\\]/.test(text)) return false;
  try { return Boolean(new URL(text).hostname); } catch { return false; }
}
module.exports = {isWebLink};

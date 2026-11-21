// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

import { createInterface } from 'node:readline';
import { project } from './adapter.mjs';

// One persistent, local process. stdout carries only correlated JSON replies.
for await (const line of createInterface({ input: process.stdin, crlfDelay: Infinity })) {
  let request;
  let response;
  try {
    request = JSON.parse(line);
    if (request.schema !== 1 || !Number.isSafeInteger(request.id)) {
      throw new Error('Unsupported Mermaid helper request.');
    }
    response = { schema: 1, id: request.id, ...project(request.source) };
  } catch (error) {
    response = { schema: 1, id: request?.id ?? null, error: error.message };
  }
  process.stdout.write(`${JSON.stringify(response)}\n`);
}

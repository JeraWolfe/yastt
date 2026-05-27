#!/usr/bin/env node
// YASTT hook dispatcher (plugin path). Runs the OS-appropriate hook script, piping the hook
// payload (stdin) straight through. Used by hooks.json so one entry works on every platform.
// Windows -> PowerShell + the .ps1 ; macOS/Linux -> bash + the .sh (needs jq).
// Always exits 0 -- a logging hook must never break the prompt.
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

try {
  const name = process.argv[2];                       // 'token_log' | 'subagent_stop'
  if (!name) process.exit(0);
  const stdin = fs.readFileSync(0);                   // the hook JSON payload
  const isWin = process.platform === 'win32';
  const script = path.join(__dirname, name + (isWin ? '.ps1' : '.sh'));
  const cmd  = isWin ? 'powershell' : 'bash';
  const args = isWin ? ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script] : [script];
  spawnSync(cmd, args, { input: stdin, stdio: ['pipe', 'inherit', 'inherit'] });
} catch (e) { /* swallow */ }
process.exit(0);

#!/usr/bin/env node
// sauron CLI - thin Node wrapper over setup.sh.
'use strict';
const { spawnSync } = require('child_process');
const path = require('path');
const fs = require('fs');

const ROOT = path.resolve(__dirname, '..');
const SETUP = path.join(ROOT, 'setup.sh');
const SKILLS_DIR = path.join(ROOT, 'skills');

const BOLD='\x1b[1m', DIM='\x1b[2m', RED='\x1b[31m', RST='\x1b[0m';

function usage() {
  console.log(`${BOLD}sauron${RST}  interactive AI orchestrator installer for offensive security

${BOLD}Usage${RST} (github: form works without npm publish)
  npx --yes github:crowx01/sauron                install (interactive; resumes on Ctrl+C)
  npx --yes github:crowx01/sauron add <skill>    install one shipped or pentesting skill
  npx --yes github:crowx01/sauron list           list shipped + pentesting-skills
  npx --yes github:crowx01/sauron sync           re-sync pentesting-skills + shipped
  npx --yes github:crowx01/sauron reset          clear checkpoint
  npx --yes github:crowx01/sauron selftest       validate shipped files (no network)
  npx --yes github:crowx01/sauron --help         this help

${DIM}From a local clone: ./setup.sh <same-verbs>   or   node bin/cli.js <verbs>${RST}

Environment:
  SAURON_PENTESTING_SKILLS_REPO   default https://github.com/crowx01/Pentesting-Skills
  SAURON_PENTESTING_SKILLS_CACHE  default ~/.cache/sauron/pentesting-skills
`);
}

function runSetup(args) {
  if (!fs.existsSync(SETUP)) {
    console.error(`${RED}✗${RST} setup.sh missing in ${ROOT}`);
    process.exit(1);
  }
  const r = spawnSync('bash', [SETUP, ...args], { stdio: 'inherit' });
  process.exit(r.status == null ? 1 : r.status);
}

const [,, cmd, ...rest] = process.argv;

switch (cmd) {
  case undefined:
  case 'install':
    runSetup([]);
    break;
  case '-h':
  case '--help':
  case 'help':
    usage();
    break;
  case 'list':
    runSetup(['list']);
    break;
  case 'add':
    if (!rest[0]) {
      console.error(`${RED}✗${RST} usage: npx --yes github:crowx01/sauron add <skill>`);
      runSetup(['list']);
      process.exit(2);
    }
    runSetup(['add', rest[0]]);
    break;
  case 'sync':
    runSetup(['sync']);
    break;
  case 'reset':
    runSetup(['reset']);
    break;
  case 'selftest': {
    const script = path.join(ROOT, 'bin', 'sauron-selftest');
    if (!fs.existsSync(script)) {
      console.error(`${RED}✗${RST} bin/sauron-selftest missing in ${ROOT}`);
      process.exit(1);
    }
    const r = spawnSync('bash', [script], { stdio: 'inherit' });
    process.exit(r.status == null ? 1 : r.status);
  }
  default:
    console.error(`${RED}✗${RST} unknown command: ${cmd}`);
    usage();
    process.exit(2);
}

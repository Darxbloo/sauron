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

${BOLD}Usage${RST}
  npx sauron                    install (interactive; resumes on Ctrl+C)
  npx sauron add <skill>        install one shipped or pentesting-skills skill
  npx sauron list               list shipped + pentesting-skills
  npx sauron sync               re-sync pentesting-skills + shipped skills
  npx sauron reset              clear installation checkpoint
  npx sauron --help             this help

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
      console.error(`${RED}✗${RST} usage: npx sauron add <skill>`);
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
  default:
    console.error(`${RED}✗${RST} unknown command: ${cmd}`);
    usage();
    process.exit(2);
}

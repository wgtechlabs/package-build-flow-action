#!/usr/bin/env node
'use strict';

// Bun builds and packs Bun projects; npm CLI supplies official trusted publishing.
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

function run(command, args, options = {}) {
  const result = spawnSync(command, args, { encoding: 'utf8', maxBuffer: 16 * 1024 * 1024, ...options });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.error) throw result.error;
  if (result.status !== 0) throw new Error(`${command} ${args[0]} failed (exit ${result.status}).`);
  return result.stdout;
}

let directory;
try {
  const [nodeMajor, nodeMinor] = process.versions.node.split('.').map(Number);
  if (nodeMajor < 22 || (nodeMajor === 22 && nodeMinor < 14)) {
    throw new Error('NPM trusted publishing requires Node.js >=22.14.0.');
  }
  const npmVersion = run('npm', ['--version']).trim();
  const parsed = /^(\d+)\.(\d+)\.(\d+)$/.exec(npmVersion);
  if (!parsed || Number(parsed[1]) < 11 || (Number(parsed[1]) === 11 &&
      (Number(parsed[2]) < 5 || (Number(parsed[2]) === 5 && Number(parsed[3]) < 1)))) {
    throw new Error('NPM trusted publishing requires npm >=11.5.1. Install a supported npm CLI before running this action.');
  }
  if (process.env.GITHUB_ACTIONS !== 'true' || process.env.RUNNER_ENVIRONMENT !== 'github-hosted' ||
      !process.env.ACTIONS_ID_TOKEN_REQUEST_URL || !process.env.ACTIONS_ID_TOKEN_REQUEST_TOKEN) {
    throw new Error('NPM trusted publishing requires a GitHub-hosted Actions runner with id-token: write permission.');
  }
  const registry = new URL(process.env.NPM_REGISTRY_URL);
  if (!['https:', 'http:'].includes(registry.protocol) || registry.username || registry.password || registry.search || registry.hash) {
    throw new Error('NPM trusted publishing requires an HTTP(S) registry URL without credentials, query, or fragment.');
  }

  directory = fs.mkdtempSync(path.join(os.tmpdir(), 'npm-oidc-'));
  if (process.env.PACKAGE_MANAGER === 'bun') {
    run('bun', ['pm', 'pack', '--destination', directory]);
  } else {
    run('npm', ['pack', '--pack-destination', directory]);
  }
  const tarballs = fs.readdirSync(directory).filter(file => file.endsWith('.tgz'));
  if (tarballs.length !== 1) throw new Error('Packing must produce exactly one tarball.');
  const tarball = path.join(directory, tarballs[0]);
  const manifestResult = spawnSync('tar', ['-xOf', tarball, 'package/package.json'], { encoding: 'utf8' });
  if (manifestResult.error || manifestResult.status !== 0) throw new Error('Cannot read the packed package manifest.');
  const manifest = JSON.parse(manifestResult.stdout);
  if (manifest.name !== process.env.NPM_PACKAGE_NAME || manifest.version !== process.env.PACKAGE_VERSION) {
    throw new Error('Packed package identity does not match the planned name and version.');
  }
  // npm accepts arbitrary publishConfig keys. Do not let credentials bypass OIDC.
  for (const key of Object.keys(manifest.publishConfig || {})) {
    if (/(^|:)(_authToken|_auth|username|_password|certfile|keyfile|token)$/i.test(key) || /:registry$/i.test(key)) {
      throw new Error('publishConfig must not contain credentials or scoped registry overrides when using OIDC.');
    }
  }

  // npm intentionally falls back to traditional auth after failed OIDC. Empty
  // configs, an isolated cwd, and a clean npm auth environment make that fail closed.
  const env = { ...process.env };
  for (const key of Object.keys(env)) {
    if (/^npm_config_/i.test(key) || /^(NPM_TOKEN|NODE_AUTH_TOKEN|NPM_ID_TOKEN|GITHUB_TOKEN)$/i.test(key)) delete env[key];
  }
  const userconfig = path.join(directory, 'user.npmrc');
  const globalconfig = path.join(directory, 'global.npmrc');
  fs.writeFileSync(userconfig, '');
  fs.writeFileSync(globalconfig, '');
  env.NPM_CONFIG_USERCONFIG = userconfig;
  env.NPM_CONFIG_GLOBALCONFIG = globalconfig;
  const args = ['publish', tarball, '--ignore-scripts', '--fetch-retries=0',
    '--registry', registry.href, '--tag', process.env.NPM_TAG];
  if (manifest.name.startsWith('@')) args.push('--access', process.env.ACCESS || 'public');
  run('npm', args, { cwd: directory, env });
} catch (error) {
  console.error(`NPM trusted publishing failed: ${error.message}`);
  process.exitCode = 1;
} finally {
  if (directory) fs.rmSync(directory, { recursive: true, force: true });
}

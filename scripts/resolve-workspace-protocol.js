#!/usr/bin/env node

/**
 * Workspace Protocol Resolution Script
 * Resolves workspace:* protocol dependencies to actual semver versions
 * before npm publish
 */

const fs = require('fs');
const path = require('path');

// Read inputs from environment
const PACKAGE_PATH = process.env.PACKAGE_PATH || '';
const DISCOVERED_PACKAGES_JSON = process.env.DISCOVERED_PACKAGES || '[]';

if (!PACKAGE_PATH) {
  console.error('❌ Error: PACKAGE_PATH environment variable is required');
  process.exit(1);
}

if (!fs.existsSync(PACKAGE_PATH)) {
  console.error(`❌ Error: Package file not found: ${PACKAGE_PATH}`);
  process.exit(1);
}

console.log('🔄 Resolving workspace protocol dependencies...');
console.log('');

// Parse discovered packages
let discoveredPackages;
try {
  discoveredPackages = JSON.parse(DISCOVERED_PACKAGES_JSON);
} catch (error) {
  console.error('❌ Error: Failed to parse DISCOVERED_PACKAGES');
  console.error(error.message);
  process.exit(1);
}

// Build a map of package name to version
const packageVersionMap = new Map();
if (Array.isArray(discoveredPackages)) {
  discoveredPackages.forEach(pkg => {
    if (pkg && pkg.name && pkg.version) {
      packageVersionMap.set(pkg.name, pkg.version);
    }
  });
}

// Read package.json
let packageJson;
try {
  const packageContent = fs.readFileSync(PACKAGE_PATH, 'utf8');
  packageJson = JSON.parse(packageContent);
} catch (error) {
  console.error(`❌ Error: Failed to read package.json at ${PACKAGE_PATH}`);
  console.error(error.message);
  process.exit(1);
}

// Track if any changes were made
let changesMade = false;
const resolvedDeps = [];

// Dependency types to check
const depTypes = ['dependencies', 'devDependencies', 'peerDependencies'];

depTypes.forEach(depType => {
  if (!packageJson[depType]) {
    return;
  }

  const deps = packageJson[depType];
  Object.keys(deps).forEach(depName => {
    const depVersion = deps[depName];
    
    // Check if it uses workspace protocol
    if (typeof depVersion === 'string' && depVersion.startsWith('workspace:')) {
      // Extract the version specifier after "workspace:"
      const specifier = depVersion.substring('workspace:'.length);
      
      // Look up the package version
      const actualVersion = packageVersionMap.get(depName);
      
      if (!actualVersion) {
        console.log(`⚠️  Warning: Workspace dependency "${depName}" not found in discovered packages`);
        console.log(`   Keeping original value: ${depVersion}`);
        return;
      }
      
      let resolvedVersion;
      
      // Resolve based on specifier type
      if (specifier === '*') {
        // workspace:* → exact version
        resolvedVersion = actualVersion;
      } else if (specifier === '^') {
        // workspace:^ → ^version
        resolvedVersion = `^${actualVersion}`;
      } else if (specifier === '~') {
        // workspace:~ → ~version
        resolvedVersion = `~${actualVersion}`;
      } else if (specifier.match(/^[\^~>=<]/)) {
        // workspace:^1.0.0 or workspace:~1.0.0 → strip prefix, keep range
        resolvedVersion = specifier;
      } else {
        // Other formats → use as-is or default to exact version
        resolvedVersion = specifier || actualVersion;
      }
      
      // Update the dependency
      deps[depName] = resolvedVersion;
      changesMade = true;
      
      resolvedDeps.push({
        name: depName,
        type: depType,
        original: depVersion,
        resolved: resolvedVersion
      });
    }
  });
});

if (changesMade) {
  console.log('📝 Resolved workspace dependencies:');
  resolvedDeps.forEach(dep => {
    console.log(`  ${dep.name} (${dep.type})`);
    console.log(`    ${dep.original} → ${dep.resolved}`);
  });
  console.log('');
  
  // Write updated package.json
  try {
    fs.writeFileSync(PACKAGE_PATH, JSON.stringify(packageJson, null, 2) + '\n', 'utf8');
    console.log('✅ Package.json updated with resolved versions');
  } catch (error) {
    console.error('❌ Error: Failed to write updated package.json');
    console.error(error.message);
    process.exit(1);
  }
} else {
  console.log('ℹ️  No workspace protocol dependencies to resolve');
}

console.log('');

#!/usr/bin/env node

/**
 * Workspace Protocol Resolution Script
 * Resolves workspace:* protocol dependencies to actual semver versions
 * before npm publish
 */

const fs = require('fs');

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
const unresolvedDeps = [];

/**
 * Resolve workspace protocol specifier to actual version
 * @param {string} specifier - The part after "workspace:" (e.g., "*", "^", "~", "^1.0.0")
 * @param {string} actualVersion - The actual version from the workspace package
 * @returns {string} - The resolved version string
 */
function resolveSpecifier(specifier, actualVersion) {
  // workspace:* → exact version
  if (specifier === '*') {
    return actualVersion;
  }
  
  // workspace:^ → ^version
  if (specifier === '^') {
    return `^${actualVersion}`;
  }
  
  // workspace:~ → ~version
  if (specifier === '~') {
    return `~${actualVersion}`;
  }
  
  // workspace:^1.0.0 or workspace:~1.0.0 or workspace:>=1.0.0
  // Strip "workspace:" prefix, keep the range specifier
  if (specifier.match(/^[\^~>=<]/)) {
    return specifier;
  }
  
  // Other formats → use as-is or default to exact version
  return specifier || actualVersion;
}

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
        // Track unresolved dependencies
        unresolvedDeps.push({
          name: depName,
          type: depType,
          original: depVersion
        });
        
        // For critical dependency types (dependencies, peerDependencies), fail
        if (depType === 'dependencies' || depType === 'peerDependencies') {
          console.error(`❌ Error: Workspace dependency "${depName}" (${depType}) not found in discovered packages`);
          console.error(`   Cannot resolve: ${depVersion}`);
          console.error(`   This would result in a broken package on the registry.`);
        } else {
          // For devDependencies, just warn
          console.log(`⚠️  Warning: Workspace dependency "${depName}" (${depType}) not found in discovered packages`);
          console.log(`   Keeping original value: ${depVersion}`);
        }
        return;
      }
      
      // Resolve the specifier to actual version
      const resolvedVersion = resolveSpecifier(specifier, actualVersion);
      
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

// Check if we have critical unresolved dependencies
const criticalUnresolved = unresolvedDeps.filter(dep => 
  dep.type === 'dependencies' || dep.type === 'peerDependencies'
);

if (criticalUnresolved.length > 0) {
  console.error('');
  console.error(`❌ Found ${criticalUnresolved.length} unresolved workspace dependencies in critical fields:`);
  criticalUnresolved.forEach(dep => {
    console.error(`   - ${dep.name} (${dep.type}): ${dep.original}`);
  });
  console.error('');
  console.error('Publishing with unresolved workspace protocols would create a broken package.');
  console.error('Ensure all workspace dependencies are discovered and available.');
  process.exit(1);
}

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

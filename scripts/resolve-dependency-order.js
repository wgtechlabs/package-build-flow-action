#!/usr/bin/env node

/**
 * Dependency Order Resolution Script
 * Performs topological sort of workspace packages based on their dependencies
 * Uses Kahn's algorithm to detect and resolve dependency order
 */

const fs = require('fs');
const path = require('path');

// Read input packages from environment (JSON array)
const PACKAGES_JSON = process.env.PACKAGES_JSON || '[]';
const GITHUB_OUTPUT = process.env.GITHUB_OUTPUT || '';

console.log('🔄 Resolving dependency order...');
console.log('');

let packages;
try {
  packages = JSON.parse(PACKAGES_JSON);
} catch (error) {
  console.error('❌ Error: Failed to parse PACKAGES_JSON');
  console.error(error.message);
  process.exit(1);
}

if (!Array.isArray(packages) || packages.length === 0) {
  console.error('❌ Error: No packages provided or invalid package array');
  process.exit(1);
}

console.log(`📦 Processing ${packages.length} package(s)`);
console.log('');

// Build package name to metadata map
const packageMap = new Map();
packages.forEach(pkg => {
  if (!pkg.name || !pkg.path) {
    console.error(`⚠️  Warning: Package missing name or path, skipping: ${JSON.stringify(pkg)}`);
    return;
  }
  packageMap.set(pkg.name, pkg);
});

// Extract workspace dependencies from a package
function getWorkspaceDependencies(packagePath) {
  try {
    const packageJsonPath = path.resolve(packagePath);
    if (!fs.existsSync(packageJsonPath)) {
      console.error(`⚠️  Warning: Package file not found: ${packagePath}`);
      return [];
    }

    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    const workspaceDeps = new Set();

    // Check all dependency types
    const depTypes = ['dependencies', 'peerDependencies', 'devDependencies'];
    
    depTypes.forEach(depType => {
      if (packageJson[depType]) {
        Object.keys(packageJson[depType]).forEach(depName => {
          // Only include if it's a workspace package
          if (packageMap.has(depName)) {
            workspaceDeps.add(depName);
          }
        });
      }
    });

    return Array.from(workspaceDeps);
  } catch (error) {
    console.error(`⚠️  Warning: Failed to read dependencies from ${packagePath}: ${error.message}`);
    return [];
  }
}

// Build dependency graph
console.log('🔍 Analyzing workspace dependencies...');
console.log('');

const dependencyGraph = new Map(); // package name -> array of workspace dependencies
const dependents = new Map(); // package name -> array of packages that depend on it
const inDegree = new Map(); // package name -> count of dependencies

// Initialize maps
packages.forEach(pkg => {
  if (!pkg.name) return;
  
  dependencyGraph.set(pkg.name, []);
  dependents.set(pkg.name, []);
  inDegree.set(pkg.name, 0);
});

// Build the graph
packages.forEach(pkg => {
  if (!pkg.name) return;
  
  const deps = getWorkspaceDependencies(pkg.path);
  dependencyGraph.set(pkg.name, deps);
  
  // Update in-degree and dependents
  deps.forEach(depName => {
    if (dependents.has(depName)) {
      dependents.get(depName).push(pkg.name);
    }
    inDegree.set(pkg.name, inDegree.get(pkg.name) + 1);
  });
  
  if (deps.length > 0) {
    console.log(`  ${pkg.name} → depends on: ${deps.join(', ')}`);
  } else {
    console.log(`  ${pkg.name} → no workspace dependencies`);
  }
});

console.log('');
console.log('🔀 Performing topological sort (Kahn\'s algorithm)...');
console.log('');

// Kahn's algorithm for topological sort
const sorted = [];
const queue = [];

// Start with packages that have no dependencies
packages.forEach(pkg => {
  if (!pkg.name) return;
  
  if (inDegree.get(pkg.name) === 0) {
    queue.push(pkg.name);
  }
});

// Process queue
while (queue.length > 0) {
  const current = queue.shift();
  sorted.push(current);
  
  // Process dependents
  const currentDependents = dependents.get(current) || [];
  currentDependents.forEach(dependent => {
    const newInDegree = inDegree.get(dependent) - 1;
    inDegree.set(dependent, newInDegree);
    
    if (newInDegree === 0) {
      queue.push(dependent);
    }
  });
}

// Check for circular dependencies
if (sorted.length !== packages.filter(p => p.name).length) {
  console.error('❌ Circular dependency detected!');
  console.error('');
  
  // Find packages involved in the cycle
  const cyclePackages = [];
  packages.forEach(pkg => {
    if (pkg.name && inDegree.get(pkg.name) > 0) {
      cyclePackages.push(pkg.name);
    }
  });
  
  console.error(`❌ Circular dependency detected among: ${cyclePackages.join(', ')}`);
  console.error('');
  console.error('Dependency graph for these packages:');
  cyclePackages.forEach(pkgName => {
    const deps = dependencyGraph.get(pkgName) || [];
    console.error(`  ${pkgName} → ${deps.join(', ') || 'none'}`);
  });
  
  process.exit(1);
}

// Build ordered package list (preserve original package metadata)
const orderedPackages = sorted.map(name => packageMap.get(name));

console.log('📋 Build order:');
orderedPackages.forEach((pkg, index) => {
  const deps = dependencyGraph.get(pkg.name) || [];
  const depInfo = deps.length > 0 ? `depends on: ${deps.join(', ')}` : 'no workspace deps';
  console.log(`  ${index + 1}. ${pkg.name} (${depInfo})`);
});

console.log('');
console.log('✅ Dependency order resolved successfully');
console.log('');

// Output the ordered packages as JSON
const orderedPackagesJson = JSON.stringify(orderedPackages);

// Write to GitHub Output if available
if (GITHUB_OUTPUT) {
  fs.appendFileSync(GITHUB_OUTPUT, `ordered-packages=${orderedPackagesJson}\n`);
}

// Also write to stdout for script consumption
console.log('ORDERED_PACKAGES=' + orderedPackagesJson);

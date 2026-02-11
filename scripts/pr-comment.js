#!/usr/bin/env node

/**
 * PR Comment Script
 * Posts informative comments on pull requests with installation instructions
 */

const https = require('https');
const fs = require('fs');
const path = require('path');

// Environment variables
const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const GITHUB_CONTEXT = JSON.parse(process.env.GITHUB_CONTEXT || '{}');
const BUILD_FLOW_TYPE = process.env.BUILD_FLOW_TYPE || 'unknown';
const PACKAGE_VERSION = process.env.PACKAGE_VERSION;
const NPM_TAG = process.env.NPM_TAG || 'latest';
const PACKAGE_PATH = process.env.PACKAGE_PATH || './package.json';
const REGISTRY = process.env.REGISTRY || 'both';
const NPM_REGISTRY_URL = process.env.NPM_REGISTRY_URL || 'https://registry.npmjs.org';
const GITHUB_REGISTRY_URL = process.env.GITHUB_REGISTRY_URL || 'https://npm.pkg.github.com';
const PACKAGE_SCOPE = process.env.PACKAGE_SCOPE || '';
const AUDIT_ENABLED = process.env.AUDIT_ENABLED === 'true';
const PR_COMMENT_TEMPLATE = process.env.PR_COMMENT_TEMPLATE || '';
const NPM_PUBLISHED = process.env.NPM_PUBLISHED === 'true';
const GITHUB_PUBLISHED = process.env.GITHUB_PUBLISHED === 'true';
const MONOREPO_MODE = process.env.MONOREPO_MODE === 'true';

// Monorepo-specific variables
const BUILD_RESULTS_JSON = process.env.BUILD_RESULTS_JSON || '[]';
const DISCOVERED_PACKAGES_JSON = process.env.DISCOVERED_PACKAGES_JSON || '[]';
const CHANGED_PACKAGES_JSON = process.env.CHANGED_PACKAGES_JSON || '[]';

// Get PR number
const prNumber = GITHUB_CONTEXT.event?.pull_request?.number;
if (!prNumber) {
  console.log('⚠️  Not a pull request event, skipping comment');
  process.exit(0);
}

const repo = GITHUB_CONTEXT.repository;
const [owner, repoName] = repo.split('/');

console.log('💬 Generating PR comment...');
console.log(`  PR: #${prNumber}`);
console.log(`  Mode: ${MONOREPO_MODE ? 'Monorepo' : 'Single Package'}`);
console.log(`  Flow Type: ${BUILD_FLOW_TYPE}`);

// Build flow descriptions
const flowDescriptions = {
  pr: {
    emoji: '🔀',
    title: 'Pull Request Build',
    description: 'Pre-release package for testing PR changes'
  },
  dev: {
    emoji: '🚀',
    title: 'Development Build',
    description: 'Development version ready for integration testing'
  },
  patch: {
    emoji: '🔧',
    title: 'Patch Build',
    description: 'Patch version for testing hotfixes'
  },
  staging: {
    emoji: '🎯',
    title: 'Release Candidate',
    description: 'Staging release candidate for final validation'
  },
  wip: {
    emoji: '🚧',
    title: 'Work in Progress',
    description: 'Experimental build from feature branch'
  }
};

const flowInfo = flowDescriptions[BUILD_FLOW_TYPE] || flowDescriptions.wip;

// Load audit results if available
// Note: In monorepo mode, audit-summary.json is written per-package.
// For now, we only show root-level audit results. Per-package audit aggregation
// would require collecting audit-summary.json files from each package directory.
let auditSection = '';
if (AUDIT_ENABLED) {
  try {
    const auditPath = path.join(process.cwd(), 'audit-summary.json');
    if (fs.existsSync(auditPath)) {
      const auditResults = JSON.parse(fs.readFileSync(auditPath, 'utf8'));
      
      auditSection = '\n\n## 🔒 Security Audit\n\n';
      
      if (auditResults.totalVulnerabilities === 0) {
        auditSection += '✅ **No vulnerabilities found**\n';
      } else {
        auditSection += `⚠️  **${auditResults.totalVulnerabilities} vulnerabilities found**\n\n`;
        auditSection += '| Severity | Count |\n';
        auditSection += '|----------|-------|\n';
        
        if (auditResults.critical > 0) {
          auditSection += `| 🔴 Critical | ${auditResults.critical} |\n`;
        }
        if (auditResults.high > 0) {
          auditSection += `| 🟠 High | ${auditResults.high} |\n`;
        }
        if (auditResults.moderate > 0) {
          auditSection += `| 🟡 Moderate | ${auditResults.moderate} |\n`;
        }
        if (auditResults.low > 0) {
          auditSection += `| 🟢 Low | ${auditResults.low} |\n`;
        }
      }
    }
  } catch (error) {
    console.error('⚠️  Could not load audit results:', error.message);
  }
}

// Generate comment body
let commentBody;

if (MONOREPO_MODE) {
  // Monorepo mode
  console.log('  Generating monorepo comment...');
  
  // Parse JSON with error handling
  let buildResults = [];
  let discoveredPackages = [];
  let changedPackages = [];
  
  try {
    buildResults = JSON.parse(BUILD_RESULTS_JSON);
    if (!Array.isArray(buildResults)) {
      console.warn('⚠️  BUILD_RESULTS_JSON is not an array, using empty array');
      buildResults = [];
    }
  } catch (error) {
    console.error('❌ Failed to parse BUILD_RESULTS_JSON:', error.message);
    buildResults = [];
  }
  
  try {
    discoveredPackages = JSON.parse(DISCOVERED_PACKAGES_JSON);
    if (!Array.isArray(discoveredPackages)) {
      console.warn('⚠️  DISCOVERED_PACKAGES_JSON is not an array, using empty array');
      discoveredPackages = [];
    }
  } catch (error) {
    console.error('❌ Failed to parse DISCOVERED_PACKAGES_JSON:', error.message);
    discoveredPackages = [];
  }
  
  try {
    changedPackages = JSON.parse(CHANGED_PACKAGES_JSON);
    if (!Array.isArray(changedPackages)) {
      console.warn('⚠️  CHANGED_PACKAGES_JSON is not an array, using empty array');
      changedPackages = [];
    }
  } catch (error) {
    console.error('❌ Failed to parse CHANGED_PACKAGES_JSON:', error.message);
    changedPackages = [];
  }
  
  console.log(`  Build results: ${buildResults.length} packages`);
  console.log(`  Discovered packages: ${discoveredPackages.length} packages`);
  console.log(`  Changed packages: ${changedPackages.length} packages`);
  
  // Create a map of build results by package name
  const buildResultsMap = {};
  buildResults.forEach(result => {
    buildResultsMap[result.name] = result;
  });
  
  // Build the packages table
  let packagesTable = '| Package | Version | Status | Install |\n';
  packagesTable += '|---------|---------|--------|---------|\n';
  
  discoveredPackages.forEach(pkg => {
    const buildResult = buildResultsMap[pkg.name];
    
    if (buildResult && buildResult.result === 'success') {
      // Check if actually published to at least one registry
      const npmPublished = buildResult['npm-published'] === 'true';
      const githubPublished = buildResult['github-published'] === 'true';
      const wasPublished = npmPublished || githubPublished;
      
      if (wasPublished) {
        // Successfully published
        const version = `\`${buildResult.version}\``;
        const status = '✅ Published';
        
        // Determine package name for install command
        // Prefer npm name, but use GitHub-scoped name if only published to GitHub
        let installName = pkg.name;
        if (!npmPublished && githubPublished) {
          // Only published to GitHub - need to determine scoped name
          if (!pkg.name.startsWith('@')) {
            // Package needs scoping for GitHub
            const repoOwner = GITHUB_CONTEXT.repository_owner || owner;
            if (PACKAGE_SCOPE) {
              const scope = PACKAGE_SCOPE.startsWith('@') ? PACKAGE_SCOPE : `@${PACKAGE_SCOPE}`;
              installName = `${scope}/${pkg.name}`;
            } else {
              installName = `@${repoOwner}/${pkg.name}`;
            }
          }
        }
        
        const installCmd = `\`npm i ${installName}@${buildResult.version}\``;
        packagesTable += `| ${pkg.name} | ${version} | ${status} | ${installCmd} |\n`;
      } else {
        // Build succeeded but not published (dry-run or publish disabled)
        const version = `\`${buildResult.version}\``;
        const status = '⚠️ Built (not published)';
        packagesTable += `| ${pkg.name} | ${version} | ${status} | — |\n`;
      }
    } else if (buildResult && buildResult.result === 'failed') {
      // Failed
      const status = '❌ Failed';
      packagesTable += `| ${pkg.name} | — | ${status} | — |\n`;
    } else {
      // Unchanged (not in build results)
      const status = '⏭️ Unchanged';
      packagesTable += `| ${pkg.name} | — | ${status} | — |\n`;
    }
  });
  
  // Build quick install section
  // Filter to packages that were actually published to at least one registry
  const successfulPackages = buildResults.filter(r => 
    r.result === 'success' && 
    (r['npm-published'] === 'true' || r['github-published'] === 'true')
  );
  let quickInstall = '';
  
  if (successfulPackages.length > 0) {
    const installCommands = successfulPackages
      .map(pkg => {
        const npmPublished = pkg['npm-published'] === 'true';
        const githubPublished = pkg['github-published'] === 'true';
        
        // Determine package name for install command
        let installName = pkg.name;
        
        // If only published to GitHub and package is unscoped, use GitHub-scoped name
        if (!npmPublished && githubPublished && !pkg.name.startsWith('@')) {
          const repoOwner = GITHUB_CONTEXT.repository_owner || owner;
          if (PACKAGE_SCOPE) {
            const scope = PACKAGE_SCOPE.startsWith('@') ? PACKAGE_SCOPE : `@${PACKAGE_SCOPE}`;
            installName = `${scope}/${pkg.name}`;
          } else {
            installName = `@${repoOwner}/${pkg.name}`;
          }
        }
        
        return `${installName}@${pkg.version}`;
      })
      .join(' ');
    quickInstall = `### 📥 Quick Install (changed packages)\n\`\`\`bash\nnpm i ${installCommands}\n\`\`\`\n`;
  } else {
    quickInstall = '### 📥 Quick Install\n\n⚠️ No packages were published to any registry.\n';
  }
  
  if (PR_COMMENT_TEMPLATE) {
    // Use custom template with variable replacements
    commentBody = PR_COMMENT_TEMPLATE
      .replace(/{BUILD_FLOW}/g, BUILD_FLOW_TYPE)
      .replace(/{PACKAGES_TABLE}/g, packagesTable)
      .replace(/{QUICK_INSTALL}/g, quickInstall)
      .replace(/{AUDIT_RESULTS}/g, auditSection);
  } else {
    // Generate default monorepo comment
    commentBody = `## 📦 Package Build Flow — Monorepo Build\n\n`;
    commentBody += `${flowInfo.emoji} **${flowInfo.title}** — ${flowInfo.description}\n\n`;
    commentBody += packagesTable + '\n';
    commentBody += quickInstall + '\n';
    commentBody += auditSection;
    commentBody += '\n---\n*This package was built automatically by the Package Build Flow action.*\n';
  }
  
} else {
  // Single package mode - existing behavior
  const packageJson = JSON.parse(fs.readFileSync(PACKAGE_PATH, 'utf8'));
  const packageName = packageJson.name;
  
  console.log(`  Package: ${packageName}@${PACKAGE_VERSION}`);
  
  // Generate installation instructions
  let installCommands = [];

  if ((REGISTRY === 'npm' || REGISTRY === 'both') && NPM_PUBLISHED) {
    installCommands.push({
      registry: 'NPM Registry',
      commands: [
        `npm install ${packageName}@${PACKAGE_VERSION}`,
        `npm install ${packageName}@${NPM_TAG}  # Use dist-tag`
      ],
      url: `${NPM_REGISTRY_URL}/${packageName}`
    });
  }

  if ((REGISTRY === 'github' || REGISTRY === 'both') && GITHUB_PUBLISHED) {
    let ghPackageName = packageName;
    let wasAutoScoped = false;
    
    if (!packageName.startsWith('@')) {
      if (PACKAGE_SCOPE) {
        // Ensure scope starts with @
        const scope = PACKAGE_SCOPE.startsWith('@') ? PACKAGE_SCOPE : `@${PACKAGE_SCOPE}`;
        ghPackageName = `${scope}/${packageName}`;
      } else {
        // Auto-scope using repository owner
        const repoOwner = GITHUB_CONTEXT.repository_owner || owner;
        ghPackageName = `@${repoOwner}/${packageName}`;
        wasAutoScoped = true;
      }
    }
    
    installCommands.push({
      registry: 'GitHub Packages',
      commands: [
        `npm install ${ghPackageName}@${PACKAGE_VERSION}`,
        `npm install ${ghPackageName}@${NPM_TAG}  # Use dist-tag`
      ],
      url: `https://github.com/${owner}/${repoName}/packages`,
      note: wasAutoScoped ? `✨ Auto-scoped as \`${ghPackageName}\` (from repository owner)` : undefined
    });
  }

  if (PR_COMMENT_TEMPLATE) {
    // Use custom template
    commentBody = PR_COMMENT_TEMPLATE
      .replace(/{BUILD_FLOW}/g, BUILD_FLOW_TYPE)
      .replace(/{PACKAGE_VERSION}/g, PACKAGE_VERSION)
      .replace(/{NPM_INSTALL}/g, installCommands.find(c => c.registry === 'NPM Registry')?.commands[0] || 'N/A')
      .replace(/{GITHUB_INSTALL}/g, installCommands.find(c => c.registry === 'GitHub Packages')?.commands[0] || 'N/A')
      .replace(/{AUDIT_RESULTS}/g, auditSection);
  } else {
    // Generate default comment
    commentBody = `## ${flowInfo.emoji} ${flowInfo.title}\n\n`;
    commentBody += `${flowInfo.description}\n\n`;
    commentBody += `### 📦 Package Information\n\n`;
    commentBody += `- **Package:** \`${packageName}\`\n`;
    commentBody += `- **Version:** \`${PACKAGE_VERSION}\`\n`;
    commentBody += `- **Dist-tag:** \`${NPM_TAG}\`\n\n`;
    commentBody += `### 📥 Installation Instructions\n\n`;

    if (installCommands.length === 0) {
      commentBody += '⚠️  Package was not published to any registry.\n';
    } else {
      installCommands.forEach(({ registry, commands, url, note }) => {
        commentBody += `#### ${registry}\n\n\`\`\`bash\n${commands.join('\n')}\n\`\`\`\n\n`;
        if (note) {
          commentBody += `${note}\n\n`;
        }
        commentBody += `[View on ${registry}](${url})\n\n`;
      });
    }

    commentBody += auditSection;
    commentBody += '\n---\n*This package was built automatically by the Package Build Flow action.*\n';
  }
}

// Post comment to PR
function postComment(body) {
  return new Promise((resolve, reject) => {
    const data = JSON.stringify({ body });
    
    const options = {
      hostname: 'api.github.com',
      port: 443,
      path: `/repos/${owner}/${repoName}/issues/${prNumber}/comments`,
      method: 'POST',
      headers: {
        'Authorization': `token ${GITHUB_TOKEN}`,
        'User-Agent': 'package-build-flow-action',
        'Content-Type': 'application/json',
        'Content-Length': data.length
      }
    };
    
    const req = https.request(options, (res) => {
      let responseData = '';
      
      res.on('data', (chunk) => {
        responseData += chunk;
      });
      
      res.on('end', () => {
        if (res.statusCode >= 200 && res.statusCode < 300) {
          resolve(JSON.parse(responseData));
        } else {
          reject(new Error(`HTTP ${res.statusCode}: ${responseData}`));
        }
      });
    });
    
    req.on('error', reject);
    req.write(data);
    req.end();
  });
}

// Execute
postComment(commentBody)
  .then((result) => {
    console.log('✅ PR comment posted successfully');
    console.log(`   Comment URL: ${result.html_url}`);
  })
  .catch((error) => {
    console.error('❌ Failed to post PR comment:', error.message);
    // Don't fail the build if comment posting fails
    process.exit(0);
  });

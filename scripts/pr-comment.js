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

// Get package details
const packageJson = JSON.parse(fs.readFileSync(PACKAGE_PATH, 'utf8'));
const packageName = packageJson.name;

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
console.log(`  Package: ${packageName}@${PACKAGE_VERSION}`);
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
  if (!packageName.startsWith('@') && PACKAGE_SCOPE) {
    ghPackageName = `${PACKAGE_SCOPE}/${packageName}`;
  }
  
  installCommands.push({
    registry: 'GitHub Packages',
    commands: [
      `npm install ${ghPackageName}@${PACKAGE_VERSION}`,
      `npm install ${ghPackageName}@${NPM_TAG}  # Use dist-tag`
    ],
    url: `https://github.com/${owner}/${repoName}/packages`
  });
}

// Load audit results if available
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

// Build comment body
let commentBody;

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
  commentBody = `## ${flowInfo.emoji} ${flowInfo.title}

${flowInfo.description}

### 📦 Package Information

- **Package:** \`${packageName}\`
- **Version:** \`${PACKAGE_VERSION}\`
- **Dist-tag:** \`${NPM_TAG}\`

### 📥 Installation Instructions

`;

  if (installCommands.length === 0) {
    commentBody += '⚠️  Package was not published to any registry.\n';
  } else {
    installCommands.forEach(({ registry, commands, url }) => {
      commentBody += `#### ${registry}\n\n\`\`\`bash\n${commands.join('\n')}\n\`\`\`\n\n`;
      commentBody += `[View on ${registry}](${url})\n\n`;
    });
  }

  commentBody += auditSection;

  commentBody += `
---
*This package was built automatically by the NPM Package Build Flow action.*
`;
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
        'User-Agent': 'npm-package-build-flow-action',
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

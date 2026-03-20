#!/usr/bin/env node

/**
 * Security Audit Script
 * Runs npm audit or bun audit and parses results for GitHub Actions
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const AUDIT_LEVEL = process.env.AUDIT_LEVEL || 'high';
const FAIL_ON_AUDIT = process.env.FAIL_ON_AUDIT === 'true';
const PACKAGE_PATH = process.env.PACKAGE_PATH || './package.json';
const PACKAGE_MANAGER = process.env.PACKAGE_MANAGER || 'auto';
const GITHUB_OUTPUT = process.env.GITHUB_OUTPUT || '';

console.log('🔒 Running security audit...');
console.log(`  Audit Level: ${AUDIT_LEVEL}`);
console.log(`  Fail on Audit: ${FAIL_ON_AUDIT}`);

const initialCwd = process.cwd();

// Change to package directory
const packageDir = path.dirname(PACKAGE_PATH);
if (packageDir !== '.') {
  process.chdir(packageDir);
}

const workspaceRoot = process.env.WORKSPACE_ROOT || process.env.GITHUB_WORKSPACE || initialCwd;

function hasLockfile(filename) {
  return fs.existsSync(path.join(process.cwd(), filename)) || fs.existsSync(path.join(workspaceRoot, filename));
}

function detectAuditTool() {
  if (PACKAGE_MANAGER && PACKAGE_MANAGER !== 'auto') {
    return PACKAGE_MANAGER === 'bun' ? 'bun' : 'npm';
  }

  if (hasLockfile('bun.lockb') || hasLockfile('bun.lock')) {
    return 'bun';
  }

  return 'npm';
}

function incrementSeverity(counts, severity) {
  if (!severity || typeof severity !== 'string') {
    return;
  }

  const normalized = severity.toLowerCase();
  if (Object.prototype.hasOwnProperty.call(counts, normalized)) {
    counts[normalized] += 1;
  } else if (normalized === 'medium') {
    // Bun/npm audit payloads may use "medium" while the action output contract uses "moderate".
    counts.moderate += 1;
  } else {
    console.warn(`⚠️  Unrecognized audit severity '${severity}', ignoring`);
  }
}

function applyMetadataVulnerabilities(target, vulnerabilities) {
  target.critical = vulnerabilities.critical || 0;
  target.high = vulnerabilities.high || 0;
  target.moderate = vulnerabilities.moderate || vulnerabilities.medium || 0;
  target.low = vulnerabilities.low || 0;
  target.info = vulnerabilities.info || 0;
}

function summarizeAuditData(auditData) {
  const counts = {
    critical: 0,
    high: 0,
    moderate: 0,
    low: 0,
    info: 0
  };

  if (auditData?.metadata?.vulnerabilities) {
    applyMetadataVulnerabilities(counts, auditData.metadata.vulnerabilities);
  } else if (auditData?.vulnerabilities && typeof auditData.vulnerabilities === 'object') {
    const vulnerabilities = auditData.vulnerabilities;
    const severityKeys = ['critical', 'high', 'moderate', 'medium', 'low', 'info'];
    const severityKeysPresent = severityKeys.filter((key) =>
      Object.prototype.hasOwnProperty.call(vulnerabilities, key)
    );

    // Some audit formats expose numeric severity totals here, while others expose per-package entries.
    const looksLikeCounts =
      severityKeysPresent.length > 0 &&
      severityKeysPresent.every((key) => typeof vulnerabilities[key] === 'number');

    if (looksLikeCounts) {
      applyMetadataVulnerabilities(counts, vulnerabilities);
    } else {
      Object.values(vulnerabilities).forEach((vuln) => incrementSeverity(counts, vuln?.severity));
    }
  } else if (auditData?.advisories && typeof auditData.advisories === 'object') {
    Object.values(auditData.advisories).forEach((advisory) => incrementSeverity(counts, advisory?.severity));
  } else if (Array.isArray(auditData)) {
    auditData.forEach((item) => incrementSeverity(counts, item?.severity));
  } else if (Array.isArray(auditData?.issues)) {
    auditData.issues.forEach((item) => incrementSeverity(counts, item?.severity));
  }

  return counts;
}

const auditTool = detectAuditTool();
const auditCommand = auditTool === 'bun' ? 'bun audit --json' : 'npm audit --json';

console.log(`  Audit Tool: ${auditTool}`);

let auditResults = {
  completed: true,
  totalVulnerabilities: 0,
  critical: 0,
  high: 0,
  moderate: 0,
  low: 0,
  info: 0
};

try {
  // Run package-manager-aware audit with JSON output
  console.log(`📊 Running ${auditTool} audit...`);
  
  let auditOutput;
  try {
    auditOutput = execSync(auditCommand, {
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
  } catch (error) {
    // npm/bun audit return non-zero exit code when vulnerabilities are found
    auditOutput = error.stdout || '{}';
  }
  
  const auditData = JSON.parse(auditOutput);
  
  // Parse vulnerability counts
  const summary = summarizeAuditData(auditData);
  auditResults.critical = summary.critical;
  auditResults.high = summary.high;
  auditResults.moderate = summary.moderate;
  auditResults.low = summary.low;
  auditResults.info = summary.info;
  auditResults.totalVulnerabilities =
    auditResults.critical +
    auditResults.high +
    auditResults.moderate +
    auditResults.low +
    auditResults.info;
  
  // Write audit summary
  const summaryPath = path.join(process.cwd(), 'audit-summary.json');
  fs.writeFileSync(summaryPath, JSON.stringify(auditResults, null, 2));
  console.log(`✅ Audit summary written to ${summaryPath}`);
  
  // Display results
  console.log('');
  console.log('📋 Audit Results:');
  console.log(`  Total Vulnerabilities: ${auditResults.totalVulnerabilities}`);
  console.log(`  Critical: ${auditResults.critical}`);
  console.log(`  High: ${auditResults.high}`);
  console.log(`  Moderate: ${auditResults.moderate}`);
  console.log(`  Low: ${auditResults.low}`);
  console.log(`  Info: ${auditResults.info}`);
  console.log('');
  
  // Set GitHub Actions outputs
  if (GITHUB_OUTPUT) {
    fs.appendFileSync(GITHUB_OUTPUT, `audit-completed=true\n`);
    fs.appendFileSync(GITHUB_OUTPUT, `total-vulnerabilities=${auditResults.totalVulnerabilities}\n`);
    fs.appendFileSync(GITHUB_OUTPUT, `critical-vulnerabilities=${auditResults.critical}\n`);
    fs.appendFileSync(GITHUB_OUTPUT, `high-vulnerabilities=${auditResults.high}\n`);
  }
  
  // Check if we should fail based on audit level
  if (FAIL_ON_AUDIT) {
    let shouldFail = false;
    
    switch (AUDIT_LEVEL) {
      case 'critical':
        shouldFail = auditResults.critical > 0;
        break;
      case 'high':
        shouldFail = auditResults.critical > 0 || auditResults.high > 0;
        break;
      case 'moderate':
        shouldFail = auditResults.critical > 0 || auditResults.high > 0 || auditResults.moderate > 0;
        break;
      case 'low':
        shouldFail = auditResults.totalVulnerabilities > 0;
        break;
    }
    
    if (shouldFail) {
      console.error(`❌ Security audit failed: Found vulnerabilities at or above '${AUDIT_LEVEL}' level`);
      process.exit(1);
    }
  }
  
  if (auditResults.totalVulnerabilities > 0) {
    console.log('⚠️  Vulnerabilities found but continuing (fail-on-audit is disabled)');
  } else {
    console.log('✅ No vulnerabilities found');
  }
  
} catch (error) {
  console.error('❌ Error running security audit:', error.message);
  auditResults.completed = false;
  
  // Still set outputs even on error
  if (GITHUB_OUTPUT) {
    fs.appendFileSync(GITHUB_OUTPUT, `audit-completed=false\n`);
    fs.appendFileSync(GITHUB_OUTPUT, `total-vulnerabilities=0\n`);
    fs.appendFileSync(GITHUB_OUTPUT, `critical-vulnerabilities=0\n`);
    fs.appendFileSync(GITHUB_OUTPUT, `high-vulnerabilities=0\n`);
  }
  
  // Don't fail the build if audit itself fails
  console.log('⚠️  Continuing despite audit error...');
}

console.log('');
console.log('✅ Audit complete');

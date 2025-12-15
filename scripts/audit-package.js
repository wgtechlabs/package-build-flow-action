#!/usr/bin/env node

/**
 * NPM Security Audit Script
 * Runs npm audit and parses results for GitHub Actions
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const AUDIT_LEVEL = process.env.AUDIT_LEVEL || 'high';
const FAIL_ON_AUDIT = process.env.FAIL_ON_AUDIT === 'true';
const PACKAGE_PATH = process.env.PACKAGE_PATH || './package.json';
const GITHUB_OUTPUT = process.env.GITHUB_OUTPUT || '';

console.log('🔒 Running security audit...');
console.log(`  Audit Level: ${AUDIT_LEVEL}`);
console.log(`  Fail on Audit: ${FAIL_ON_AUDIT}`);

// Change to package directory
const packageDir = path.dirname(PACKAGE_PATH);
if (packageDir !== '.') {
  process.chdir(packageDir);
}

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
  // Run npm audit with JSON output
  console.log('📊 Running npm audit...');
  
  let auditOutput;
  try {
    auditOutput = execSync('npm audit --json', { 
      encoding: 'utf8',
      stdio: ['pipe', 'pipe', 'pipe']
    });
  } catch (error) {
    // npm audit returns non-zero exit code when vulnerabilities are found
    auditOutput = error.stdout || '{}';
  }
  
  const auditData = JSON.parse(auditOutput);
  
  // Parse vulnerability counts
  if (auditData.metadata && auditData.metadata.vulnerabilities) {
    const vulns = auditData.metadata.vulnerabilities;
    auditResults.critical = vulns.critical || 0;
    auditResults.high = vulns.high || 0;
    auditResults.moderate = vulns.moderate || 0;
    auditResults.low = vulns.low || 0;
    auditResults.info = vulns.info || 0;
    auditResults.totalVulnerabilities = 
      auditResults.critical + 
      auditResults.high + 
      auditResults.moderate + 
      auditResults.low + 
      auditResults.info;
  }
  
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

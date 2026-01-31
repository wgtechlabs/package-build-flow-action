# NPM Package Build Flow Action

Automated NPM package versioning, building, and publishing with intelligent flow detection for NPM Registry and GitHub Packages.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- 🔄 **Intelligent Flow Detection**: Automatically determines build type based on GitHub context
- 📦 **Dual Registry Support**: Publish to NPM Registry and/or GitHub Packages
- ✨ **Auto-Scoping**: Automatically scopes packages for GitHub Packages using repository owner
- 🏷️ **Smart Versioning**: SemVer versioning with pre-release tags
- 🔒 **Security Scanning**: Built-in npm audit integration
- 💬 **PR Comments**: Automatic installation instructions in pull requests
- 🎯 **Dist-tag Management**: Non-latest tags for pre-releases to keep production clean
- 🚀 **Zero Configuration**: Works out of the box with sensible defaults

## Quick Start

### Basic Usage

```yaml
name: Build and Publish

on:
  pull_request:
  push:
    branches:
      - main
      - dev

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      - uses: wgtechlabs/package-build-flow-action@v1
        with:
          npm-token: ${{ secrets.NPM_TOKEN }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
          registry: 'both'
          # package-scope not needed - auto-scoped for GitHub Packages! ✨
```

## Flow Detection

The action automatically detects the build flow based on GitHub context:

| Flow Type | Trigger | Version Format | NPM Tag | Description |
|-----------|---------|----------------|---------|-------------|
| **pr** | PR → dev branch | `{base}-pr.{sha}` | `pr` | Pre-release for testing PR changes |
| **dev** | PR dev→main OR push to dev | `{base}-dev.{sha}` | `dev` | Development version for integration testing |
| **patch** | PR → main (not from dev) | `{base+1}-patch.{sha}` | `patch` | Patch version for hotfixes |
| **staging** | Push to main | `{base}-rc.{number}` | `rc` | Release candidate for final validation |
| **wip** | Other branches | `{base}-wip.{sha}` | `wip` | Experimental build from feature branch |

### Flow Examples

#### PR to Dev Branch
```
Event: pull_request
Base: dev
Head: feature/new-feature
Version: 1.2.3-pr.abc1234
Tag: pr
```

#### Push to Dev Branch
```
Event: push
Branch: dev
Version: 1.2.3-dev.abc1234
Tag: dev
```

#### PR from Dev to Main
```
Event: pull_request
Base: main
Head: dev
Version: 1.2.3-dev.abc1234
Tag: dev
```

#### Push to Main (Staging/RC)
```
Event: push
Branch: main
Version: 1.2.3-rc.123456
Tag: rc
```

#### Patch PR to Main
```
Event: pull_request
Base: main
Head: hotfix/critical-bug
Version: 1.2.4-patch.abc1234
Tag: patch
```

## Inputs

### Registry Configuration

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `registry` | Target registry: `npm`, `github`, or `both` | `both` | No |
| `npm-token` | NPM access token | - | If publishing to NPM |
| `npm-registry-url` | NPM registry URL | `https://registry.npmjs.org` | No |
| `github-token` | GitHub token for GitHub Packages | `${{ github.token }}` | No |
| `github-registry-url` | GitHub Packages registry URL | `https://npm.pkg.github.com` | No |
| `package-scope` | Package scope for GitHub Packages (e.g., `@myorg`). If not provided, automatically uses repository owner | - | No |

### Branch Configuration

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `main-branch` | Name of main/production branch | `main` | No |
| `dev-branch` | Name of development branch | `dev` | No |

### Package Configuration

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `package-path` | Path to package.json | `./package.json` | No |
| `build-script` | NPM script to run before publishing | `build` | No |
| `version-prefix` | Prefix for version tags | - | No |

### Security Configuration

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `audit-enabled` | Enable npm audit security scanning | `true` | No |
| `audit-level` | Minimum severity level: `critical`, `high`, `moderate`, `low` | `high` | No |
| `fail-on-audit` | Fail build if vulnerabilities found | `false` | No |

### PR Comment Configuration

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `pr-comment-enabled` | Enable PR comments with installation instructions | `true` | No |
| `pr-comment-template` | Custom PR comment template | - | No |

### Publishing Configuration

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `publish-enabled` | Enable publishing to registry | `true` | No |
| `dry-run` | Perform dry run without publishing | `false` | No |

## Outputs

| Output | Description |
|--------|-------------|
| `package-version` | Generated package version |
| `registry-urls` | Installation commands for each registry |
| `build-flow-type` | Detected flow type (pr, dev, patch, staging, wip) |
| `short-sha` | Short commit SHA |
| `npm-published` | Whether published to NPM (true/false) |
| `github-published` | Whether published to GitHub Packages (true/false) |
| `audit-completed` | Whether security audit completed |
| `total-vulnerabilities` | Total vulnerabilities found |
| `critical-vulnerabilities` | Critical vulnerabilities count |
| `high-vulnerabilities` | High vulnerabilities count |

## Configuration Guide

### NPM Registry Setup

1. Create an NPM access token at https://www.npmjs.com/settings/tokens
2. Add the token as a repository secret: `NPM_TOKEN`
3. Configure the action:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    registry: 'npm'
    npm-token: ${{ secrets.NPM_TOKEN }}
```

### GitHub Packages Setup

GitHub Packages requires all packages to be scoped (e.g., `@owner/package-name`). The action provides **automatic scope detection** to make this seamless:

#### 🎯 Automatic Scope Detection

The action automatically scopes your package using this priority order:

1. **Explicit scope from `package-scope` input** → Uses provided scope
2. **Existing scope in package.json** → Uses scope from package name
3. **Repository owner** → **Automatically uses `@{repository-owner}`** ✨

This means **most users don't need to configure anything** - the action will automatically scope packages using your repository owner!

#### Scoping Outcomes

| Your package.json | package-scope Input | GitHub Packages Publishes As |
|-------------------|---------------------|------------------------------|
| `"name": "mypackage"` | _(empty)_ | `@owner/mypackage` ✨ Auto-scoped! |
| `"name": "mypackage"` | `@custom` | `@custom/mypackage` |
| `"name": "@org/mypackage"` | _(any)_ | `@org/mypackage` |

#### Basic Setup (Zero Configuration)

For most cases, you don't need to provide `package-scope`:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    registry: 'github'
    github-token: ${{ secrets.GITHUB_TOKEN }}
    # package-scope not needed - auto-scoped as @{owner}!
```

#### Custom Scope (Optional)

If you want to use a different scope than the repository owner:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    registry: 'github'
    github-token: ${{ secrets.GITHUB_TOKEN }}
    package-scope: '@myorg'
```

### Dual Registry Publishing

Publish to both NPM and GitHub Packages. GitHub Packages will use auto-scoping if needed:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    registry: 'both'
    npm-token: ${{ secrets.NPM_TOKEN }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    # package-scope optional - auto-scoped for GitHub Packages
```

Or with custom scope:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    registry: 'both'
    npm-token: ${{ secrets.NPM_TOKEN }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    package-scope: '@myorg'  # Use custom scope
```

## Versioning Strategy

### SemVer Compliance

All versions follow Semantic Versioning (SemVer) format: `MAJOR.MINOR.PATCH[-prerelease]`

- **Base Version**: Read from package.json
- **Pre-release Suffix**: Automatically added based on flow type
- **Dist-tags**: Used to hide pre-releases from `npm install` defaults

### Dist-tag Strategy

Pre-release versions use non-latest dist-tags to prevent accidental installation:

```bash
# Latest production version (no tag needed)
npm install mypackage

# Pre-release versions require explicit tag or version
npm install mypackage@dev
npm install mypackage@1.2.3-dev.abc1234

# Production releases use 'latest' tag (default)
npm install mypackage@latest
```

### Version Increment Rules

- **PR to dev**: Uses base version with `-pr.{sha}` suffix
- **Dev branch**: Uses base version with `-dev.{sha}` suffix
- **Patch PR**: Increments patch version with `-patch.{sha}` suffix
- **Staging (main)**: Uses base version with `-rc.{number}` suffix

## Security Scanning

The action includes built-in npm audit integration:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    audit-enabled: 'true'
    audit-level: 'high'
    fail-on-audit: 'true'
```

Audit results are:
- Displayed in action logs
- Included in PR comments
- Available as action outputs
- Optionally fail the build

## PR Comments

Automatic PR comments include:

- 📦 Package information (name, version, dist-tag)
- 📥 Installation instructions for each registry
- 🏷️ Dist-tag shortcuts
- 🔒 Security audit results (if enabled)
- 🔗 Links to registry pages

### Custom Comment Template

Create a custom PR comment format:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    pr-comment-template: |
      ## Build Complete
      
      Version: {PACKAGE_VERSION}
      Flow: {BUILD_FLOW}
      
      Install: {NPM_INSTALL}
      
      {AUDIT_RESULTS}
```

Template variables:
- `{BUILD_FLOW}`: Flow type
- `{PACKAGE_VERSION}`: Generated version
- `{NPM_INSTALL}`: NPM install command
- `{GITHUB_INSTALL}`: GitHub Packages install command
- `{AUDIT_RESULTS}`: Security audit summary

## Advanced Examples

### Full-Featured Workflow

```yaml
name: Advanced Build and Publish

on:
  pull_request:
    branches: [main, dev]
  push:
    branches: [main, dev]

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      pull-requests: write
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      - uses: wgtechlabs/package-build-flow-action@v1
        id: build
        with:
          # Registries
          registry: 'both'
          npm-token: ${{ secrets.NPM_TOKEN }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
          package-scope: '@myorg'
          
          # Branches
          main-branch: 'main'
          dev-branch: 'develop'
          
          # Package
          package-path: './package.json'
          build-script: 'build'
          
          # Security
          audit-enabled: 'true'
          audit-level: 'high'
          fail-on-audit: 'false'
          
          # PR Comments
          pr-comment-enabled: 'true'
      
      - name: Display Results
        run: |
          echo "Version: ${{ steps.build.outputs.package-version }}"
          echo "Flow Type: ${{ steps.build.outputs.build-flow-type }}"
          echo "NPM Published: ${{ steps.build.outputs.npm-published }}"
          echo "GitHub Published: ${{ steps.build.outputs.github-published }}"
```

### Production Release Workflow

```yaml
name: Production Release

on:
  release:
    types: [published]

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      # Update version in package.json to release version
      - name: Update Version
        run: |
          VERSION=${GITHUB_REF#refs/tags/v}
          npm version $VERSION --no-git-tag-version
      
      - uses: wgtechlabs/package-build-flow-action@v1
        with:
          registry: 'both'
          npm-token: ${{ secrets.NPM_TOKEN }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
          package-scope: '@myorg'
          audit-enabled: 'true'
          fail-on-audit: 'true'
```

### Dry Run Mode

Test the action without publishing:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    dry-run: 'true'
    npm-token: ${{ secrets.NPM_TOKEN }}
```

## Troubleshooting

### Package Not Published

**Issue**: Package doesn't appear on the registry

**Solutions**:
- Check `npm-token` is valid and has publish permissions
- Verify package name is not already taken
- For GitHub Packages, ensure package name is scoped
- Check action logs for error messages

### Authentication Failed

**Issue**: 401 Unauthorized errors

**Solutions**:
- Verify tokens are correctly set in repository secrets
- For GitHub Packages, ensure `packages: write` permission
- Check token hasn't expired
- For NPM, ensure token type is "Automation" or "Publish"

### Version Already Exists

**Issue**: Cannot publish version that already exists

**Solutions**:
- The action generates unique versions with commit SHA
- If still failing, check if version was manually published
- Verify flow detection is working correctly

### GitHub Packages Scope Issues

**Issue**: Package name must be scoped

**Solutions**:
- Set `package-scope` input: `@myorg`
- Or update package.json name to include scope: `@myorg/package-name`
- Ensure scope matches your GitHub organization

### Security Audit Failures

**Issue**: Build fails due to vulnerabilities

**Solutions**:
- Set `fail-on-audit: 'false'` to continue despite vulnerabilities
- Update dependencies to fix vulnerabilities
- Adjust `audit-level` to be less strict
- Review audit output in action logs

### PR Comments Not Appearing

**Issue**: No comments on pull requests

**Solutions**:
- Ensure `pull-requests: write` permission is granted
- Check `pr-comment-enabled` is set to `'true'`
- Verify `github-token` has correct permissions
- Only works on pull_request events

## Examples

See the [examples](./examples) directory for complete workflow examples:

- [basic-workflow.yml](./examples/basic-workflow.yml) - Simple workflow example
- [advanced-workflow.yml](./examples/advanced-workflow.yml) - Full-featured workflow
- [release-workflow.yml](./examples/release-workflow.yml) - Production release workflow

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Support

- 📖 [Documentation](https://github.com/wgtechlabs/package-build-flow-action)
- 🐛 [Issue Tracker](https://github.com/wgtechlabs/package-build-flow-action/issues)
- 💬 [Discussions](https://github.com/wgtechlabs/package-build-flow-action/discussions)

## Related Actions

- [Container Build Flow Action](https://github.com/wgtechlabs/container-build-flow-action) - Similar action for container images

---

Made with ❤️ by [WG Technology Labs](https://github.com/wgtechlabs)

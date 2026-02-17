# Package Build Flow Action

![GitHub Repo Banner](https://ghrb.waren.build/banner?header=Package+Build+Flow+%F0%9F%93%A6%E2%99%BB%EF%B8%8F&subheader=Automated+NPM+package+versioning%2C+building%2C+and+publishing.&bg=016EEA-016EEA&color=FFFFFF&headerfont=Google+Sans+Code&subheaderfont=Sour+Gummy&watermarkpos=bottom-right)
<!-- Created with GitHub Repo Banner by Waren Gonzaga: https://ghrb.waren.build -->

Automated NPM package versioning, building, and publishing with intelligent flow detection for NPM Registry and GitHub Packages.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Features

- 🔄 **Intelligent Flow Detection**: Automatically determines build type based on GitHub context
- 📦 **Dual Registry Support**: Publish to NPM Registry and/or GitHub Packages
- 🏢 **Monorepo Support**: Process multiple packages independently with their own versions
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
| **release** | GitHub Release (standard) | `{tag}` (with leading `v` stripped, e.g., `v1.0.0` → `1.0.0`) | `latest` | Production release from GitHub release event |
| **release** | GitHub Release (pre-release) | `{tag}` (with leading `v` stripped) | `{prerelease-id}` (or `prerelease` if no identifier is detected) | Pre-release from GitHub release event (e.g., beta, alpha) |
| **pr** | PR → dev branch | `{base}-pr.{sha}` | `pr` | Pre-release for testing PR changes |
| **dev** | PR dev→main OR push to dev | `{base}-dev.{sha}` | `dev` | Development version for integration testing |
| **patch** | PR → main (not from dev) | `{base}-patch.{sha}` | `patch` | Hotfix pre-release for testing |
| **staging** | Push to main | `{base}-staging.{sha}` | `staging` | Staging version for final validation before release |
| **wip** | Other branches | `{base}-wip.{sha}` | `wip` | Experimental build from feature branch |

### Flow Examples

#### GitHub Release (Production)
```
Event: release
Release Type: Standard Release
Tag: v1.0.0
Version: 1.0.0
NPM Tag: latest
```

#### GitHub Release (Pre-release)
```
Event: release
Release Type: Pre-release
Tag: v1.0.0-beta.1
Version: 1.0.0-beta.1
NPM Tag: beta
```

#### GitHub Release (Pre-release - staging tag)
```
Event: release
Release Type: Pre-release
Tag: v1.2.3-staging.abc1234
Version: 1.2.3-staging.abc1234
NPM Tag: staging
```

> [!WARNING]
> **Avoid using `staging` as a prerelease identifier in GitHub Releases.**
>
> The `staging` npm dist-tag is automatically used by the push-to-main flow (e.g., `1.2.3-staging.abc1234`). If you also create a GitHub Release with a `staging` prerelease identifier (e.g., `v1.2.3-staging.abc1234`), both flows will publish under the same `staging` dist-tag. This means whichever version is published last will overwrite the `staging` tag pointer, and running `npm install mypackage@staging` will resolve to that last-published version instead of the one you might expect.
>
> This won't break anything — both versions remain available by their exact version number (e.g., `npm install mypackage@1.2.3-staging.abc1234`). It only affects which version the `staging` dist-tag shortcut points to. If you want to avoid this overlap, use a different prerelease identifier for your GitHub Releases that doesn't collide with any of the built-in flow tags (`pr`, `dev`, `patch`, `staging`, `wip`).

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

#### Push to Main (Staging)
```
Event: push
Branch: main
Version: 1.2.3-staging.abc1234
Tag: staging
```

#### Patch PR to Main
```
Event: pull_request
Base: main
Head: hotfix/critical-bug
Version: 1.2.3-patch.abc1234
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
| `package-scope` | Package scope for GitHub Packages (e.g., `@myorg`). If not provided, uses the repository owner only when the package name in `package.json` is unscoped; if the package name is already scoped, its existing scope is kept | - | No |

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
| `package-manager` | Package manager to use: `npm`, `yarn`, `pnpm`, `bun`, or `auto` (auto-detects from lockfile) | `auto` | No |
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
| `access` | Package access level for scoped packages: `public` or `restricted` | `public` | No |

### Monorepo Configuration

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `monorepo` | Enable monorepo mode | `false` | No |
| `package-paths` | Comma-separated list of package.json paths (monorepo mode only). Takes priority over workspace-detection. Either this OR workspace-detection with valid workspaces field is required when monorepo is true. | - | Conditional* |
| `workspace-detection` | Auto-detect workspaces from the package.json resolved from `package-path` (default `./package.json`). Reads its `workspaces` field and discovers all non-private packages. | `true` | No |
| `changed-only` | Only build/publish packages that changed relative to the event-specific git diff base (monorepo mode only). Uses git diff to detect changes. | `true` | No |
| `dependency-order` | Build packages in dependency order using topological sort (monorepo mode only). Analyzes workspace dependencies and builds packages in the correct order. Set to `false` to use discovery order. | `true` | No |

*Required when `monorepo: 'true'` AND (`workspace-detection: 'false'` OR no `workspaces` field in the package.json resolved from `package-path`)

## Outputs

| Output | Description |
|--------|-------------|
| `package-version` | Generated package version (single-package mode) |
| `registry-urls` | Installation commands for each registry (single-package mode) |
| `build-flow-type` | Detected flow type (pr, dev, patch, staging, wip) (single-package mode) |
| `short-sha` | Short commit SHA (single-package mode) |
| `npm-published` | Whether published to NPM (true/false) (single-package mode) |
| `github-published` | Whether published to GitHub Packages (true/false) (single-package mode) |
| `audit-completed` | Whether security audit completed (single-package mode) |
| `total-vulnerabilities` | Total vulnerabilities found (single-package mode) |
| `critical-vulnerabilities` | Critical vulnerabilities count (single-package mode) |
| `high-vulnerabilities` | High vulnerabilities count (single-package mode) |
| `build-results` | JSON array of per-package build results (monorepo mode only) |
| `discovered-packages` | JSON array of discovered packages with name, version, path, and dir (monorepo mode with workspace-detection only) |
| `package-count` | Number of discovered publishable packages (monorepo mode with workspace-detection only) |
| `changed-packages` | JSON array of packages with changes (monorepo mode with changed-only only) |
| `changed-count` | Number of changed packages (monorepo mode with changed-only only) |

### Monorepo Build Results Format

When `monorepo: 'true'`, the `build-results` output contains a JSON array:

```json
[
  {
    "name": "@tinyclaw/core",
    "version": "1.0.0-dev.abc1234",
    "result": "success"
  },
  {
    "name": "@tinyclaw/plugin-discord",
    "version": "1.2.0-dev.abc1234",
    "result": "success"
  },
  {
    "name": "@tinyclaw/cli",
    "version": "2.0.0-dev.abc1234",
    "result": "failed",
    "error": "Build failed"
  }
]
```

## Configuration Guide

### Package Manager Selection

The action supports multiple package managers with automatic detection:

#### Auto-Detection (Default)

When `package-manager: 'auto'` (default), the action automatically selects the package manager based on lockfile presence:

1. If `bun.lockb` exists → Uses **Bun** (legacy binary format, Bun < v1.2)
2. If `bun.lock` exists → Uses **Bun** (text-based format, Bun v1.2+)
3. If `pnpm-lock.yaml` exists → Uses **pnpm**
4. If `yarn.lock` exists → Uses **Yarn**
5. If `package-lock.json` exists → Uses **npm**
6. Neither → Falls back to **npm**

This ensures lockfile consistency and preserves backward compatibility. The action checks for `bun.lockb` first to support legacy Bun projects, then checks for `bun.lock` for modern Bun v1.2+ projects. **Note:** If both `bun.lockb` and `bun.lock` exist in a project, `bun.lockb` takes precedence to ensure consistent behavior for projects in transition.

#### Manual Selection

Explicitly specify the package manager:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    package-manager: 'pnpm'  # or 'npm', 'yarn', 'bun'
    npm-token: ${{ secrets.NPM_TOKEN }}
```

#### Package Manager Examples

##### Bun

For Bun-based projects, install both Node.js (for publishing) and Bun (for building):

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-node@v4
    with:
      node-version: '20'

  - uses: oven-sh/setup-bun@v2
    with:
      bun-version: latest

  - uses: wgtechlabs/package-build-flow-action@v1
    with:
      package-manager: 'bun'  # or 'auto' to detect from bun.lockb or bun.lock
      npm-token: ${{ secrets.NPM_TOKEN }}
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

##### pnpm

For pnpm-based projects:

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: pnpm/action-setup@v2
    with:
      version: 8

  - uses: actions/setup-node@v4
    with:
      node-version: '20'
      cache: 'pnpm'

  - uses: wgtechlabs/package-build-flow-action@v1
    with:
      package-manager: 'pnpm'  # or 'auto' to detect from pnpm-lock.yaml
      npm-token: ${{ secrets.NPM_TOKEN }}
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

##### Yarn

For Yarn-based projects:

```yaml
steps:
  - uses: actions/checkout@v4

  - uses: actions/setup-node@v4
    with:
      node-version: '20'
      cache: 'yarn'

  - uses: wgtechlabs/package-build-flow-action@v1
    with:
      package-manager: 'yarn'  # or 'auto' to detect from yarn.lock
      npm-token: ${{ secrets.NPM_TOKEN }}
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

**Note:** This action always uses the npm CLI for the final publish step, regardless of the selected package manager. While Bun, pnpm, and Yarn can publish to the npm registry, this action standardizes on npm for publishing to ensure consistent behavior across environments.

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

#### Scoped Package Access

When publishing scoped packages (e.g., `@org/package-name`) to NPM, the action defaults to `--access public` to avoid 402 payment errors. Scoped packages are private by default on npm, but most open-source packages should be public.

**Default Behavior (Public Access):**

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    registry: 'npm'
    npm-token: ${{ secrets.NPM_TOKEN }}
    # access: 'public' is the default - scoped packages will be public
```

**Private Package Publishing (Requires Paid NPM Plan):**

If you have a paid NPM plan and want to publish private scoped packages:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    registry: 'npm'
    npm-token: ${{ secrets.NPM_TOKEN }}
    access: 'restricted'  # Publishes as private package
```

**Alternative: Use publishConfig in package.json**

You can also set the access level in your `package.json`:

```json
{
  "name": "@myorg/my-package",
  "publishConfig": {
    "access": "public"
  }
}
```

The action's `access` input will override `publishConfig` if both are specified.

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
- **Patch PR**: Uses base version with `-patch.{sha}` suffix
- **Staging (main)**: Uses base version with `-staging.{sha}` suffix

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

The action automatically detects GitHub release events and publishes packages with the correct version from the release tag. No manual version updates needed!

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
      
      # No manual version update needed - automatically uses release tag!
      - uses: wgtechlabs/package-build-flow-action@v1
        with:
          registry: 'both'
          npm-token: ${{ secrets.NPM_TOKEN }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
          package-scope: '@myorg'
          audit-enabled: 'true'
          fail-on-audit: 'true'
```

**How it works:**
- **Standard Release (v1.0.0)**: Publishes `1.0.0` with `latest` npm tag
- **Pre-release (v1.0.0-beta.1)**: Publishes `1.0.0-beta.1` with `beta` npm tag
- **Staging Release (v1.2.3-staging.abc1234)**: Publishes `1.2.3-staging.abc1234` with `staging` npm tag

### Dry Run Mode

Test the action without publishing:

```yaml
- uses: wgtechlabs/package-build-flow-action@v1
  with:
    dry-run: 'true'
    npm-token: ${{ secrets.NPM_TOKEN }}
```

### Monorepo Support

Process multiple packages in a monorepo with independent versioning.

#### Automatic Workspace Discovery

The action can automatically discover packages from your workspace configuration:

```yaml
name: Monorepo Build and Publish

on:
  push:
    branches: [main, dev]
  pull_request:
    branches: [main, dev]

jobs:
  build-monorepo:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      - name: Build and Publish Multiple Packages
        id: build
        uses: wgtechlabs/package-build-flow-action@v2
        with:
          # Enable monorepo mode
          monorepo: 'true'
          
          # Auto-discover packages from workspaces (default: true)
          # No package-paths needed!
          
          # Registry configuration
          registry: 'both'
          npm-token: ${{ secrets.NPM_TOKEN }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Display Discovered Packages
        run: |
          echo "Discovered ${{ steps.build.outputs.package-count }} packages:"
          echo '${{ steps.build.outputs.discovered-packages }}' | jq '.'
      
      - name: Display Build Results
        run: |
          echo "Build Results:"
          echo '${{ steps.build.outputs.build-results }}' | jq '.'
```

**Root package.json with workspaces:**
```json
{
  "name": "my-monorepo",
  "private": true,
  "workspaces": [
    "core",
    "apps/*",
    "plugins/*"
  ]
}
```

The action will:
- Read the `workspaces` field from root `package.json`
- Resolve glob patterns like `apps/*` and `plugins/*`
- Skip packages with `"private": true`
- Process all discovered publishable packages

#### Manual Package List

You can also explicitly specify packages (takes priority over workspace detection):

```yaml
name: Monorepo Build and Publish

on:
  push:
    branches: [main, dev]
  pull_request:
    branches: [main, dev]

jobs:
  build-monorepo:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    
    steps:
      - uses: actions/checkout@v4
      
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      
      - name: Build and Publish Multiple Packages
        id: build
        uses: wgtechlabs/package-build-flow-action@v2
        with:
          # Enable monorepo mode
          monorepo: 'true'
          
          # List all packages (comma-separated)
          package-paths: 'core/package.json,plugins/plugin-discord/package.json,apps/cli/package.json'
          
          # Registry configuration
          registry: 'both'
          npm-token: ${{ secrets.NPM_TOKEN }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
      
      - name: Display Build Results
        run: |
          echo "Build Results:"
          echo '${{ steps.build.outputs.build-results }}' | jq '.'
```

**Key Features:**
- Each package gets its own version based on its `package.json`
- Packages are processed sequentially
- If one package fails, remaining packages still attempt to build/publish
- Returns JSON array with per-package results
- Works with `dry-run` and `publish-enabled: false`
- Supports both workspace auto-discovery and explicit package lists
- Automatically resolves `workspace:*` protocol dependencies before publishing

#### Automatic Change Detection

By default, the action detects which packages changed and only builds/publishes those packages:

```yaml
- name: Build and Publish Changed Packages
  uses: wgtechlabs/package-build-flow-action@v2
  with:
    monorepo: 'true'
    # changed-only: 'true' (default - only build changed packages)
    npm-token: ${{ secrets.NPM_TOKEN }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

**How it works:**
- **Pull Request**: Compares against PR base branch to detect changed files
- **Push**: Compares against previous commit (`HEAD~1`)
- **Release**: Compares against previous git tag
- Maps changed files to their owning workspace package
- Root config files (`package.json`, `tsconfig.json`, lockfiles) mark ALL packages as changed
- Automatically handles shallow clones by fetching necessary history
- Falls back to building all packages if git diff fails (safe default)

**Example output:**
```json
{
  "changed-packages": [
    {"name": "@tinyclaw/core", "path": "core/package.json"}
  ],
  "changed-count": 1
}
```

**To disable change detection and always build all packages:**
```yaml
- name: Build All Packages
  uses: wgtechlabs/package-build-flow-action@v2
  with:
    monorepo: 'true'
    changed-only: 'false'  # Disable change detection
    npm-token: ${{ secrets.NPM_TOKEN }}
```

**Benefits:**
- ⚡ Faster CI/CD - skip unchanged packages
- 💰 Reduced CI costs - fewer builds
- 🎯 No manual changesets needed - automatic detection
- 🔒 Safe fallbacks - builds all packages if detection fails

**Example Output:**
```json
[
  {
    "name": "@tinyclaw/core",
    "version": "1.0.0-dev.abc1234",
    "result": "success"
  },
  {
    "name": "@tinyclaw/plugin-discord",
    "version": "1.2.0-dev.abc1234",
    "result": "success"
  }
]
```

#### Dependency-Aware Build Ordering

The action automatically orders packages based on their workspace dependencies using topological sort when workspace metadata is available. This ensures dependencies are built before their dependents.

**Requirements:**
- Requires `workspace-detection: 'true'` (default) with valid workspace packages discovered
- When using explicit `package-paths` without workspace discovery, ordering is not available

**Example:**
```yaml
- name: Build Packages in Dependency Order
  uses: wgtechlabs/package-build-flow-action@v2
  with:
    monorepo: 'true'
    # dependency-order: 'true' (default - build in dependency order)
    npm-token: ${{ secrets.NPM_TOKEN }}
```

**How it works:**
- Analyzes `dependencies`, `peerDependencies`, and `devDependencies` in each package.json
- Filters to only workspace-internal dependencies (ignores external npm packages)
- Performs topological sort using Kahn's algorithm
- Builds packages in the correct order (dependencies before dependents)
- Detects and reports circular dependencies with clear error messages
- Supports `workspace:*` protocol and standard version ranges

**Example dependency graph:**
```
@tinyclaw/core           → no workspace deps
@tinyclaw/plugin-discord → depends on @tinyclaw/core
@tinyclaw/plugin-slack   → depends on @tinyclaw/core
tinyclaw (CLI)           → depends on @tinyclaw/core, @tinyclaw/plugin-discord, @tinyclaw/plugin-slack
```

**Build order output:**
```
📋 Build order:
  1. @tinyclaw/core (no workspace deps)
  2. @tinyclaw/plugin-discord (depends on: @tinyclaw/core)
  3. @tinyclaw/plugin-slack (depends on: @tinyclaw/core)
  4. tinyclaw (depends on: @tinyclaw/core, @tinyclaw/plugin-discord, @tinyclaw/plugin-slack)
```

**Circular dependency detection:**
If circular dependencies are found, the build fails with a clear error:
```
❌ Circular dependency detected among: @tinyclaw/plugin-a, @tinyclaw/plugin-b

Dependency graph for these packages:
  @tinyclaw/plugin-a → @tinyclaw/plugin-b
  @tinyclaw/plugin-b → @tinyclaw/plugin-a
```

**To disable dependency ordering and use discovery order:**
```yaml
- name: Build in Discovery Order
  uses: wgtechlabs/package-build-flow-action@v2
  with:
    monorepo: 'true'
    dependency-order: 'false'  # Disable dependency ordering
    npm-token: ${{ secrets.NPM_TOKEN }}
```

**Benefits:**
- 🔗 Correct build order - dependencies built before dependents
- 🚀 Reliable monorepo builds - no dependency resolution failures
- 🔍 Early error detection - circular dependencies caught immediately
- 💎 Works with complex dependency graphs including diamond dependencies

#### Workspace Protocol Resolution

The action automatically resolves `workspace:*` protocol dependencies to actual semver versions before publishing to npm. This ensures that published packages are installable from the registry, as `workspace:*` is not a valid semver range on npm.

**Supported workspace protocols:**
- `workspace:*` → resolves to exact version (e.g., `1.2.3`)
- `workspace:^` → resolves to caret range (e.g., `^1.2.3`)
- `workspace:~` → resolves to tilde range (e.g., `~1.2.3`)
- `workspace:^1.0.0` → strips prefix, keeps range (e.g., `^1.0.0`)

**Example package.json before resolution:**
```json
{
  "name": "@myorg/app",
  "version": "2.0.0",
  "dependencies": {
    "@myorg/core": "workspace:*",
    "@myorg/utils": "workspace:^"
  },
  "peerDependencies": {
    "@myorg/core": "workspace:~"
  }
}
```

**After resolution (when @myorg/core is v1.2.3 and @myorg/utils is v3.4.5):**
```json
{
  "name": "@myorg/app",
  "version": "2.0.0",
  "dependencies": {
    "@myorg/core": "1.2.3",
    "@myorg/utils": "^3.4.5"
  },
  "peerDependencies": {
    "@myorg/core": "~1.2.3"
  }
}
```

**How it works:**
- Automatically detects workspace protocol dependencies in all dependency fields
- Looks up actual versions from discovered workspace packages
- Resolves versions before running `npm publish`
- Restores original `package.json` after publishing
- Works with pnpm, Yarn, and Bun workspace protocols

**Benefits:**
- ✅ Published packages are installable from the registry
- 🔄 Automatic resolution - no manual version updates needed
- 🛡️ Original workspace protocols preserved in source control
- 📦 Compatible with pnpm, Yarn Berry, and Bun workspaces

**Discovered Packages Output:**
```json
[
  {
    "name": "@tinyclaw/core",
    "version": "1.0.0",
    "path": "core/package.json",
    "dir": "core"
  },
  {
    "name": "@tinyclaw/plugin-discord",
    "version": "1.2.0",
    "path": "plugins/plugin-discord/package.json",
    "dir": "plugins/plugin-discord"
  }
]
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
- [monorepo-workflow.yml](./examples/monorepo-workflow.yml) - Monorepo multi-package workflow

## Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting a Pull Request.

This repository follows the [Clean Commit](https://github.com/wgtechlabs/clean-commit) convention with emoji-based commit messages. See [CONTRIBUTING.md](CONTRIBUTING.md) for details.

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

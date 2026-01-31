---
alwaysApply: true
always_on: true
trigger: always_on
applyTo: "**"
description: Clean Commit Convention
---

# Clean Commit Convention

This repository follows the **Clean Commit** convention for all commit messages.

Reference: https://github.com/wgtechlabs/clean-commit

## Commit Message Format

```text
<emoji> <type>: <description>
<emoji> <type>(<scope>): <description>
```

## The 9 Types

| Emoji | Type | What it covers |
|:-----:|------|----------------|
| 📦 | `new` | Adding new features, files, or capabilities |
| 🔧 | `update` | Changing existing code, refactoring, improvements |
| 🗑️ | `remove` | Removing code, files, features, or dependencies |
| 🔒 | `security` | Security fixes, patches, vulnerability resolutions |
| ⚙️ | `setup` | Project configs, CI/CD, tooling, build systems |
| ☕ | `chore` | Maintenance tasks, dependency updates, housekeeping |
| 🧪 | `test` | Adding, updating, or fixing tests |
| 📖 | `docs` | Documentation changes and updates |
| 🚀 | `release` | Version releases and release preparation |

## Scope

The scope is optional and should be the name of the affected component or module (e.g., api, auth, workflow, scripts, etc).

## Description

The description contains a succinct description of the change:

- Use lowercase for type
- Use present tense ("add" not "added")
- No period at the end
- Keep description under 72 characters

## Body (Optional)

The body should include the motivation for the change and contrast this with previous behavior.

## Footer (Optional)

The footer should contain any information about Breaking Changes and is also the place to reference GitHub issues that this commit closes.

Breaking Changes should start with the word `BREAKING CHANGE:` with a space or two newlines.

## Examples

### Adding new features
```
📦 new: user authentication system

Implement OAuth2 authentication flow for third-party login providers.
Supports Google, GitHub, and Microsoft providers.

Closes #123
```

### Updating existing code
```
🔧 update(api): improve error handling

Enhanced error handling to provide more detailed error messages
and proper HTTP status codes for all API endpoints.

Fixes #456
```

### Removing code or dependencies
```
🗑️ remove(deps): unused lodash dependency

Removed lodash as it's no longer used after refactoring utility functions.
```

### Security fixes
```
🔒 security: patch XSS vulnerability in input validation

Fixed cross-site scripting vulnerability by properly sanitizing user inputs
before rendering them in the UI.

BREAKING CHANGE: Input validation now rejects certain special characters
that were previously allowed.
```

### Project setup and configuration
```
⚙️ setup: add eslint configuration

Added ESLint with recommended rules and project-specific overrides.
```

### Maintenance and housekeeping
```
☕ chore: update npm dependencies

Updated all npm packages to their latest compatible versions.
```

### Testing
```
🧪 test: add unit tests for auth service

Added comprehensive unit tests for authentication service covering
login, logout, and token validation.
```

### Documentation
```
📖 docs: update installation instructions

Added troubleshooting section for common installation issues and
updated setup steps for Node.js 20.
```

### Releases
```
🚀 release: version 1.0.0

First stable release with all core features implemented and tested.
```

### With scope
```
🔧 update(workflow): improve build performance

Optimized build workflow by caching dependencies and running
tests in parallel.
```

## Benefits

- Visual recognition with emojis makes commit types instantly recognizable
- Automatically generate CHANGELOGs
- Clear categorization of changes
- Communicate the nature of changes to teammates and users
- Make it easier for people to contribute by showing a structured history

## Tools

The repository may use tools like:
- **commitlint**: To validate commit messages
- **husky**: To run commit message validation on pre-commit
- **semantic-release**: To automatically determine version and generate changelog

## Enforcement

All commits must follow this convention. Pull requests with non-compliant commit messages will be rejected.

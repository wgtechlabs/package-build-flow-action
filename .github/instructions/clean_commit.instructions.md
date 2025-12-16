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
<type>(<scope>): <subject>

<body>

<footer>
```

## Types

- **feat**: A new feature
- **fix**: A bug fix
- **docs**: Documentation only changes
- **style**: Changes that do not affect the meaning of the code (white-space, formatting, etc)
- **refactor**: A code change that neither fixes a bug nor adds a feature
- **perf**: A code change that improves performance
- **test**: Adding missing tests or correcting existing tests
- **build**: Changes that affect the build system or external dependencies
- **ci**: Changes to CI configuration files and scripts
- **chore**: Other changes that don't modify src or test files
- **revert**: Reverts a previous commit

## Scope

The scope should be the name of the affected component or module (e.g., parser, compiler, api, auth, etc).

## Subject

The subject contains a succinct description of the change:

- Use the imperative, present tense: "change" not "changed" nor "changes"
- Don't capitalize the first letter
- No period (.) at the end

## Body

The body should include the motivation for the change and contrast this with previous behavior.

## Footer

The footer should contain any information about Breaking Changes and is also the place to reference GitHub issues that this commit closes.

Breaking Changes should start with the word `BREAKING CHANGE:` with a space or two newlines.

## Examples

### Feature with scope
```
feat(auth): add OAuth2 authentication

Implement OAuth2 authentication flow for third-party login providers.
Supports Google, GitHub, and Microsoft providers.

Closes #123
```

### Bug fix
```
fix(parser): handle null values in JSON parsing

Previously, null values would cause a TypeError. Now they are properly
handled and converted to null in the output.

Fixes #456
```

### Breaking change
```
feat(api): change response format for user endpoints

BREAKING CHANGE: User API responses now return camelCase field names
instead of snake_case. Update your client code accordingly.

Before: { user_name: "john" }
After: { userName: "john" }

Closes #789
```

### Documentation
```
docs(readme): update installation instructions

Add troubleshooting section for common installation issues.
```

### Chore
```
chore(deps): update dependencies to latest versions
```

## Benefits

- Automatically generate CHANGELOGs
- Automatically determine semantic version bump
- Communicate the nature of changes to teammates and users
- Trigger build and publish processes
- Make it easier for people to contribute by showing a structured history

## Tools

The repository may use tools like:
- **commitlint**: To validate commit messages
- **husky**: To run commit message validation on pre-commit
- **semantic-release**: To automatically determine version and generate changelog

## Enforcement

All commits must follow this convention. Pull requests with non-compliant commit messages will be rejected.

# Contributing to Package Build Flow Action

Thank you for your interest in contributing to this project! We welcome contributions from the community.

## Commit Message Convention

This repository follows the **Clean Commit** convention with emoji-based commit messages.

Reference: https://github.com/wgtechlabs/clean-commit

### Format

```text
<emoji> <type>: <description>
<emoji> <type>(<scope>): <description>
```

### The 9 Types

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

### Rules

- Use lowercase for type
- Use present tense ("add" not "added")
- No period at the end
- Keep description under 72 characters

### Examples

- `📦 new: user authentication system`
- `🔧 update(api): improve error handling`
- `🗑️ remove(deps): unused lodash dependency`
- `🔒 security: patch XSS vulnerability`
- `⚙️ setup: add eslint configuration`
- `☕ chore: update npm dependencies`
- `🧪 test: add unit tests for auth service`
- `📖 docs: update installation instructions`
- `🚀 release: version 1.0.0`

## How to Contribute

1. **Fork the repository** and clone it locally
2. **Create a new branch** for your feature or fix:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Make your changes** following the project conventions
4. **Commit your changes** using the Clean Commit convention:
   ```bash
   git commit -m "📦 new: your feature description"
   ```
5. **Push to your fork**:
   ```bash
   git push origin feature/your-feature-name
   ```
6. **Open a Pull Request** with a clear description of your changes

## Pull Request Guidelines

- Ensure your PR description clearly describes the problem and solution
- Include the relevant issue number if applicable
- Update documentation as needed
- Follow the commit message convention for all commits
- Keep PRs focused - one feature or fix per PR

## Code Style

- Follow existing code style and conventions
- Use meaningful variable and function names
- Add comments for complex logic
- Keep functions small and focused

## Testing

- Add tests for new features
- Ensure existing tests pass
- Test your changes thoroughly before submitting

## Questions?

Feel free to open an issue for any questions or concerns.

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

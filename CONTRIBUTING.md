# Contributing to detect_unused_code

Thank you for your interest in contributing to `detect_unused_code`! Contributions from the community are what make open-source tools thrive.

## How to Contribute

### 1. Reporting Issues
- Check the [issue tracker](https://github.com/mdalhagg/detect_unused_code/issues) to ensure the issue has not already been reported.
- Open a new issue with a clear title and description, including reproduction steps and Dart/Flutter SDK version.

### 2. Suggesting Features
- Open an issue outlining the suggested feature, use case, and rationale.

### 3. Code Contributions & Pull Requests
1. Fork the repository and create your branch from `main`:
   ```bash
   git checkout -b feature/my-new-feature
   ```
2. Make your improvements.
3. Ensure zero external runtime dependencies are introduced.
4. Run static analysis and ensure 100% clean check:
   ```bash
   dart analyze
   dart format .
   dart pub publish --dry-run
   ```
5. Submit a Pull Request targeting `main`.

## Code Style
- Follow the official [Effective Dart](https://dart.dev/effective-dart) guidelines.
- Maintain 100% dartdoc documentation comments on all public API elements.

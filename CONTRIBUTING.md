# Contributing to bikes-virtlocks

Thank you for interest in contributing! This document explains the development workflow and guidelines.

## Development Setup

### 1. Prerequisites
- Flutter SDK 3.9+
- Git
- Your favorite Dart/Flutter IDE (VS Code, Android Studio, or IntelliJ)

### 2. Clone and Setup
```bash
git clone https://github.com/adam-ai-rob/bikes-virtlocks.git
cd bikes-virtlocks
flutter pub get
flutter pub run build_runner build
```

### 3. Run in Development
```bash
flutter run -d macos  # or windows/linux
```

## Workflow

### Branch Naming
- Feature: `feature/lock-encryption`
- Bugfix: `fix/connection-timeout`
- Documentation: `docs/setup-guide`
- Refactor: `refactor/state-machine`

### Commit Message Format
```
<type>(<scope>): <subject>

<body>

Fixes #123
```

**Types:** feat, fix, docs, refactor, test, chore, perf

**Example:**
```
feat(locks): add encryption for shadow updates

- Implement AES-256 encryption for sensitive lock state
- Add key management service
- Update shadow publish to use encrypted payload

Fixes #45
```

### Pull Request Process
1. Create feature branch from `main`
2. Make changes and commit regularly
3. Push to your fork
4. Create PR with clear description
5. Ensure CI passes (linting, tests)
6. Request review from maintainers
7. Address feedback and merge when approved

## Code Style

### Formatting
```bash
# Format all Dart files
flutter format lib test

# Or automatically on save (configure IDE)
```

### Linting
```bash
# Check for issues
flutter analyze

# Or use Biome (configured in analysis_options.yaml)
dart run biome check lib/
```

### Code Generation
After modifying models, providers, or using `@freezed`:
```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Architecture Guidelines

### Layer Structure
Files should go in the appropriate layer:

```
features/<feature>/
├── domain/
│   ├── entities/      # Data models (use @freezed)
│   └── use_cases/     # Business logic (optional)
├── presentation/
│   ├── screens/       # Full page screens
│   ├── widgets/       # Reusable widgets
│   └── viewmodels/    # UI state (optional)
└── providers/         # Riverpod StateNotifiers & Providers
```

### Naming Conventions
- **Classes**: `PascalCase` (e.g., `LockSimulator`)
- **Functions/Variables**: `camelCase` (e.g., `simulateLockState`)
- **Constants**: `CONSTANT_CASE` or `camelCase` in classes
- **Private**: Prefix with `_` (e.g., `_internalMethod`)
- **Files**: `snake_case` (e.g., `lock_simulator.dart`)

### State Management (Riverpod)
- Use `StateNotifier` for complex state changes
- Use `Provider` for computed/filtered state
- Use `FutureProvider` for async operations
- Avoid mutable state; use `copyWith()` for immutability

Example:
```dart
class LocksNotifier extends StateNotifier<LocksState> {
  LocksNotifier(this._ref) : super(const LocksState());

  // State is immutable, use copyWith for updates
  void updateLock(String thingId, LockState lock) {
    final locks = Map<String, LockState>.from(state.locks);
    locks[thingId] = lock;
    state = state.copyWith(locks: locks);  // ← Immutable update
  }
}

final locksProvider = StateNotifierProvider<LocksNotifier, LocksState>(...);
```

### Error Handling
All async operations should handle errors gracefully:
```dart
Future<void> connect() async {
  try {
    // Operation
  } catch (e, stackTrace) {
    AppLogger.error('Failed to connect', e, stackTrace);
    state = state.copyWith(error: e.toString());
  }
}
```

## Testing

### Running Tests
```bash
# Run all tests
flutter test

# Run specific file
flutter test test/locks_test.dart

# Run with coverage
flutter test --coverage
```

### Writing Tests
- Create test files in `test/` directory
- Test name should match implementation: `lib/features/locks/...` → `test/features/locks/...`
- Use `group()` to organize related tests
- Use mocks for external dependencies

Example:
```dart
void main() {
  group('LocksNotifier', () {
    test('auto-locks when timer expires', () {
      final notifier = LocksNotifier(ref);
      notifier.unlock('lock-1', durationSeconds: 5);
      
      expect(notifier.state.locks['lock-1']!.isLocked, false);
      
      // Fast-forward timer
      // Verify auto-lock
      expect(notifier.state.locks['lock-1']!.isLocked, true);
    });
  });
}
```

## Documentation

### Code Comments
- Comment "why", not "what"
- Use `///` for public APIs
- Keep comments up-to-date with code changes

Good:
```dart
/// Decrement timer and auto-lock when it reaches zero.
/// 
/// This simulates physical lock behavior where the lock automatically
/// re-engages after the configured unlock duration expires.
void _updateTimers() { ... }
```

Bad:
```dart
/// Update timers
void _updateTimers() { ... }
```

### README Updates
- Update README.md when adding features
- Document new screens in Architecture section
- Add examples for new public APIs
- Keep setup instructions current

## Performance

### Guidelines
- Avoid rebuilding entire lock list on single update (use immutable updates)
- Throttle MQTT message publishing (don't spam)
- Use `const` constructors where possible
- Profile before optimizing (`flutter run --profile`)

### MQTT Best Practices
- Subscribe only to needed topics
- Unsubscribe when not needed
- Batch shadow updates when possible
- Don't publish on every timer tick (use heartbeat)

## Security

### Sensitive Data
- Never commit AWS credentials
- Use `.env` files for local secrets (add to `.gitignore`)
- Store certificates securely (Hive encryption if available)
- Log errors but don't log sensitive data

## Deployment

### Release Checklist
- [ ] All tests pass
- [ ] Code formatted (`flutter format`)
- [ ] No lint warnings (`flutter analyze`)
- [ ] README and docs updated
- [ ] Version bumped in `pubspec.yaml`
- [ ] Changelog updated
- [ ] Tested on all platforms (macOS, Windows, Linux)

## Getting Help

- **Documentation**: See README.md
- **Issues**: Check existing GitHub issues
- **Discussions**: Start a GitHub discussion for questions
- **Slack**: Join the bikes-api Slack channel

## Code Review Process

### What We Look For
- ✅ Code follows style guidelines
- ✅ Tests cover new functionality
- ✅ Documentation is clear
- ✅ No breaking changes without discussion
- ✅ Performance impact considered

### Feedback Format
We aim to be constructive and supportive:
- Compliment good work
- Explain the reasoning behind suggestions
- Offer solutions, not just problems
- Welcome questions and discussion

---

Thank you for contributing! 🚀

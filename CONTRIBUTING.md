# Contributing

## Branches

| Branch | Purpose |
|---|---|
| `main` | released code; changes only via release merges |
| `develop` | integration branch; PRs target this |
| `feature/<name>` | one change per branch |

## Setup

```bash
cd src
flutter pub get
dart run build_runner build
```

`*.g.dart` files and the platform folders are generated and not committed.
Re-run `build_runner` after every change under `lib/core/database/`.

## Before opening a PR

```bash
flutter analyze --fatal-infos   # must be clean — never silence with // ignore
flutter test                    # must pass
```

## Commit messages

- Imperative mood ("Add Brack fixture", not "Added …").
- First line under 72 characters.
- Reference issues as `Fixes #42`.

## Recipes

### Changing the database schema

1. Edit or add the table under `lib/core/database/tables/`.
2. Bump `schemaVersion` in `app_database.dart` and add the `if (from < N)`
   step to `onUpgrade` in the `MigrationStrategy`; dump the previous schema
   into `test/fixtures/` and extend `test/database/migration_test.dart`.
3. `dart run build_runner build`.
4. Extend `test/database/daos_test.dart`.
5. If the backup shape changes, bump `BackupService.kFormatVersion`.
6. Update `doc/REQUIREMENTS.md` §3 and `doc/ARCHITECTURE.md` §3.

### Supporting a new shop

Usually nothing: if the shop publishes schema.org `Product` JSON-LD or OG
product meta tags, the generic extractor reads it. Add a reduced HTML fixture
under `test/fixtures/` and an extractor test. Do not add CSS-selector scrapers
or anti-bot workarounds (REQUIREMENTS 4.2.3).

### Native platform changes

Platform folders are not committed. Express every native change (permission,
plist key, entitlement) as a patch step in `.github/workflows/build.yml`.

## Releasing

```bash
git tag v0.1.0
git push origin v0.1.0
```

`release.yml` runs the gate, builds all platforms and creates the GitHub
Release.

## Code style

- Riverpod 2 with manual providers; singletons are overridden in `main.dart`
  and throw when not overridden.
- Constructor injection; no service locator, no global mutable state.
- Services return values or sealed results and never show UI.
- Comments explain *why*, not *what*.
- Relative imports inside `lib/`.

### PR checklist

- [ ] `flutter analyze --fatal-infos` clean
- [ ] `flutter test` passes
- [ ] New behaviour has a test, or the PR says why it cannot
- [ ] `doc/` and `CLAUDE.md` updated where behaviour or structure changed
- [ ] Any new platform trap recorded in `CLAUDE.md`

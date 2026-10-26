# Contributing to NorthStar Health

Thanks for helping. NorthStar handles workout and account data, so a few areas need extra care. This page tells you what to work on, how to set up, and what a mergeable PR looks like.

## Before you start

1. **Pick an open issue** and comment that you're taking it. Issues labelled `good first issue` or `help wanted` are ready to work on.
2. **Check the scope.** UI and accessibility, tests, documentation, Wear OS/watchOS non-recording UI and bug fixes are open to everyone. Changes to sync, authentication, storage, the database, contracts, CI, ADRs, permissions or dependencies need a maintainer-approved issue first. The full list is in [AGENTS.md → External contributions](AGENTS.md#external-contributions).
3. **Read the rules for your area:** [AGENTS.md](AGENTS.md), the nested `AGENTS.md` of the app you touch, and [docs/DESIGN_SYSTEM.md](docs/DESIGN_SYSTEM.md) for UI work. They apply to humans and AI agents alike.

## Setup

Flutter **3.47.7 stable**. The Flutter project root is `apps/mobile/`, not the repository root.

```sh
cd apps/mobile
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

These checks need no backend. **Running the app** needs a Supabase project because sign-in is mandatory: create your own free one by following [docs/CONTRIBUTOR_SUPABASE_SETUP.md](docs/CONTRIBUTOR_SUPABASE_SETUP.md). Never use, request or share the maintainer's keys.

Other gates:

```sh
# repository and protocol contracts (repo root)
python3 -m pip install 'jsonschema==4.23.0' 'PyYAML==6.0.2'
python3 -m unittest discover -s tool -p 'test_*.py'

# Wear OS (JDK 17, Android SDK 35)
cd apps/wear_os && ./gradlew :app:assembleDebug
```

ObjectBox code generation: `dart run build_runner build --delete-conflicting-outputs` from `apps/mobile`. Commit both `lib/objectbox.g.dart` and `lib/objectbox-model.json`.

## Making changes

- Branch from `main`, one issue per PR, keep it small.
- UI comes from the shared kit in `apps/mobile/lib/core/design/`. `test/design_kit_guard_test.dart` fails if a feature uses raw `TextField`, `AlertDialog`, `SnackBar` and similar.
- Support light and dark mode, phones and tablets, and large text.
- Bug fixes start with a failing test.
- Use synthetic test data only. Never commit keys, `supabase.local.json` or real health exports.
- Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/), for example `fix(train): keep rest timer running after rotation`.

## Using AI coding agents

AI-assisted PRs are welcome on the same terms as any other. `CLAUDE.md` and `AGENTS.md` are written so agents pick up the project rules automatically. You remain responsible for the result:

- Say in the PR whether an agent wrote any of it, and which one.
- Read the whole diff and run the checks yourself before opening the PR.
- Answer review comments in your own words. PRs where nobody can explain the change will be closed.

## Pull requests

- Fill in the PR template. Mark checks you could not run as "not run" rather than ticking them.
- Include light and dark screenshots for UI changes.
- CI must pass and the maintainer must approve before merge. Contributors and agents never merge.
- Expect review on sync, data and security changes to take longer; that's deliberate.

## Reporting security issues

Don't open a public issue for a vulnerability, especially anything affecting account isolation, authentication or data upload. Use GitHub's **Report a vulnerability** option on the repository's Security tab.

## License

By contributing, you agree that your contributions are licensed under the [Mozilla Public License 2.0](LICENSE), the same license as the project.

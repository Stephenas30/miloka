# Miloka — Agent Guide

## What is this

Flutter multi-platform card/board game app (Belote, Ludo, Rami, Billard). Backend is Supabase (auth, DB, realtime, storage). UI language: French.

## Quick commands

```bash
flutter pub get          # install deps
flutter run              # launch app
flutter test             # run all tests
flutter analyze          # static analysis (uses flutter_lints)
```

No CI, no Makefile, no custom scripts. No single-test runner beyond `flutter test`.

## Architecture

- **Entry**: `lib/main.dart` → inits Supabase → `SplashScreen` → `HomeScreen` (logged in) or `OnbordingScreen`
- **State**: Provider (`ChangeNotifierProvider`). Only `AuthProvider` is wired at the root. No Riverpod despite README claim.
- **Services** (all in `lib/service/`, singular — NOT `services/`):
  - `SupabaseService` — singleton, inits client + Google Sign-In, handles auth, avatars, online status
  - `AuthService` — static methods for email/password login, token persistence via `flutter_secure_storage`
  - `FriendsService` — friend requests, game invites via `amis` table
  - `TeamLobbyService` — singleton, Belote team lobby via `teams` table
  - `LudoMultiplayerService` — singleton, Supabase Realtime channels for Ludo
  - `StatsService` — stub (game stats logic removed)
  - `StorageService` — token/email persistence with `FlutterSecureStorage`
- **Game logic** (`lib/game/`): Belote engine (`belote_game_logic.dart`, `belote_rules.dart`, `call_system.dart`, `deck.dart`), Ludo engine (`ludo/ludo_engine.dart`). Pure Dart, no Flutter deps.
- **Screens** (`lib/screens/`): One screen per flow. `SplashScreen` → `HomeScreen`, `LoginScreen`, `RegisterScreen`, `ProfileScreen`/`ProfilScreen` (note: both exist), `BeloteScreen`, `LudoScreen`, etc.
- **Assets**: SVG cards in `assets/images/card/`. Format: `{suit}-{rank}.svg` (e.g. `carreau-9.svg`). Ranks: 7,8,9,10,J,Q,K,A. Suits: carreau, coeur, pique, trefle.

## Key gotchas

- **Supabase creds are hardcoded** in `lib/service/supabase_service.dart:19-20`. Do not commit new credentials.
- **`flutter_secure_storage` is in `dev_dependencies`** — it's used in production code (`storage_service.dart`). Likely a bug; if adding new secure storage usage, be aware.
- **Two profile screens**: `profile_screen.dart` and `profil_screen.dart` both exist. Check which one is imported where before editing.
- **Service singletons**: `SupabaseService`, `TeamLobbyService`, `LudoMultiplayerService` use the `_instance` pattern. `AuthService` and `FriendsService` use static methods or instantiate fresh — do not assume all services are singletons.
- **No `.env` file**: All config is in Dart source. Environment-specific values are not externalized.
- **`game_provider.dart` is empty** — game state is managed inline in screens and `BeloteGameLogic`.

## Database (Supabase)

Schema documented in `bdd.md` and `SUPABASE_SETUP.md` (trust `bdd.md` for canonical schema). Tables: `users`, `amis`, `games`, `player_games`, `teams`. The `amis` table uses a `status` column (`pending`/`accepted`) and a `send_partie` column for game invites — migration documented in `SUPABASE_SETUP.md` §11.

## Testing

- `test/widget_test.dart` — `ProfileScreen` widget test
- `test/ludo_engine_test.dart` — `LudoEngine` multiplayer snapshot test
- Tests use `flutter_test`. No mocking framework. No integration tests.
- Run with `flutter test`. No way to run a single test file without filtering.

## Style notes

- Dart code is in French (variable names, comments, UI strings).
- No custom lint rules beyond `flutter_lints` defaults.
- No code generation, no build_runner, no freezed, no json_serializable.

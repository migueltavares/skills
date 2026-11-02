# Laravel checklist

Check each item against the code. An item that doesn't apply gets one line saying why.

## Authorization

- Every controller action, Livewire action and API route checks permission through a policy, a gate, or `authorize()`. Being logged in is not permission.
- Every record loaded from a URL is checked against the current user or team, through a policy or a query scoped to them. Changing an id in the URL must not reach another account's record. `scopeBindings()` only ties a child to its parent in the URL, so the parent still needs that check.
- Filament: the user model implements `canAccessPanel()`, every resource has a policy, and actions such as bulk delete, export and impersonation are checked too.
- Livewire: public properties that hold ids or prices are locked (`#[Locked]`) or checked again on the server.

## Input and models

- Models list `$fillable`, or keep a non-empty `$guarded`. `$guarded = []`, `forceFill` and `Model::unguard()` appear only where a user can't control the input.
- Every write goes through a FormRequest or `validate()`. Files are validated by MIME type and size, stored outside `public/`, and served through a controller that checks access.
- Raw SQL (`DB::raw`, `whereRaw`, `orderByRaw`, `selectRaw`) uses bindings, never values joined into the string.
- Blade output uses `{{ }}`. Each `{!! !!}` is justified, and its content sanitised.

## Secrets and config

- `.env` is not in git, and `.env.example` holds no real values. Search the history too: `git log -p -S <prefix>` for key prefixes.
- Production runs with `APP_DEBUG=false`, and `APP_KEY` is set and not shared between environments.
- Logs don't record passwords, tokens or personal data in full. Check `Log::` calls and exception context.
- Sessions use secure cookies in production (`SESSION_SECURE_COOKIE=true`).

## Abuse

- Login, password reset, registration, contact forms and any endpoint that sends email or SMS are rate limited.
- Signed URLs protect links in emails, such as downloads and unsubscribes.

## Data and queries

- No N+1 queries on list pages or in exports. Turn on `Model::preventLazyLoading()` outside production to find them.
- Columns used in `where`, `orderBy` and joins on large tables have indexes. Check with `EXPLAIN` against a copy of real data.
- Exports and reports run in chunks or in a queue, never as one query over the whole table.
- Migrations that drop columns or tables, or rewrite data, are reversible or have a backup step in their deploy notes.

## Jobs and operations

- The scheduler runs, and a missed run is noticed. Failed jobs are stored and reported.
- Queue workers restart on deploy (`queue:restart`).
- Backups run, leave the server, and a restore has been tested.
- The deploy runs tests first, then migrations, then clears caches (`optimize:clear`, then `optimize`).

## Versions

- PHP and Laravel versions are within their security support windows.
- `composer audit` and `npm audit` show no high or critical advisories without a reason.
- CI runs on the same PHP version as production, and tests run on a database like production's, or SQLite with known gaps written down.

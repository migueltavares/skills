# Repo guard for a Laravel app

The machine guard stops agents. This guard lives in the repo, so it also stops a human, a CI job, or an agent on a machine without the hook. `RefreshDatabase` runs after `createApplication()`, so a check there runs before any table is dropped.

## 1. TestCase

Laravel 11 and later: add this to `tests/TestCase.php`, keeping whatever the class already has.

```php
<?php

namespace Tests;

use Illuminate\Foundation\Testing\TestCase as BaseTestCase;
use RuntimeException;

abstract class TestCase extends BaseTestCase
{
    public function createApplication()
    {
        $app = parent::createApplication();

        $connection = $app['config']->get('database.default');

        static::guardTestDatabase(
            $connection,
            $app['config']->get("database.connections.{$connection}.database"),
            $app->configurationIsCached(),
        );

        return $app;
    }

    /**
     * Tests run only on SQLite in memory or a database named for testing,
     * so RefreshDatabase can never drop real tables.
     */
    public static function guardTestDatabase(?string $connection, ?string $database, bool $configCached): void
    {
        if ($configCached) {
            throw new RuntimeException('The config is cached, so tests would ignore phpunit.xml and use the real database. Run `php artisan config:clear`, then run the tests again.');
        }

        $inMemory = $connection === 'sqlite' && $database === ':memory:';
        $namedForTests = $database !== null && str_contains($database, 'test');

        if (! $inMemory && ! $namedForTests) {
            throw new RuntimeException("Tests stopped before touching connection [{$connection}], database [{$database}]. Use SQLite in memory, or a database whose name contains \"test\".");
        }
    }
}
```

Laravel 10 and earlier keep `createApplication()` in `tests/CreatesApplication.php`. Put the `guardTestDatabase(...)` call there, just before `return $app;`, and the static method in `TestCase`.

## 2. phpunit.xml

Inside `<php>`:

```xml
<env name="DB_CONNECTION" value="sqlite"/>
<env name="DB_DATABASE" value=":memory:"/>
```

Leave out `force="true"`, so a CI job can still point tests at a MariaDB database named `testing`.

## 3. A test for the guard

Prove the guard with direct calls, never by aiming the suite at a real database. Pest version, in `tests/Unit/TestDatabaseGuardTest.php`:

```php
<?php

use Tests\TestCase;

it('stops on a real database', function () {
    TestCase::guardTestDatabase('mysql', 'app', false);
})->throws(RuntimeException::class);

it('stops when the config is cached', function () {
    TestCase::guardTestDatabase('sqlite', ':memory:', true);
})->throws(RuntimeException::class);

it('allows SQLite in memory and test databases', function () {
    expect(fn () => TestCase::guardTestDatabase('sqlite', ':memory:', false))->not->toThrow(RuntimeException::class);
    expect(fn () => TestCase::guardTestDatabase('mariadb', 'testing', false))->not->toThrow(RuntimeException::class);
});
```

The guard is done when this file passes and the full suite still passes.

## 4. CI (offer it, add it on a yes)

SQLite accepts queries that fail on MariaDB and MySQL in production (`ONLY_FULL_GROUP_BY`, implicit `ON UPDATE`, strict mode). A second job runs the suite on production's database server and PHP version. Read both versions, and the server's `sql_mode` (`SELECT @@GLOBAL.sql_mode;`), from the project's AGENTS.md. When they are missing, ask the user.

```yaml
  tests-mariadb:
    runs-on: ubuntu-latest
    services:
      mariadb:
        image: mariadb:<production version>
        env:
          MARIADB_DATABASE: testing
          MARIADB_ROOT_PASSWORD: password
        ports: ['3306:3306']
        options: >-
          --health-cmd="healthcheck.sh --connect --innodb_initialized"
          --health-interval=10s --health-retries=5
    env:
      DB_CONNECTION: mariadb
      DB_HOST: 127.0.0.1
      DB_DATABASE: testing
      DB_USERNAME: root
      DB_PASSWORD: password
    steps:
      - uses: actions/checkout@v4
      - uses: shivammathur/setup-php@v2
        with:
          php-version: '<production PHP version>'
      - run: mysql -h127.0.0.1 -uroot -ppassword -e "SET GLOBAL sql_mode='<production sql_mode>'"
      - run: composer install --no-interaction --prefer-dist
      - run: php artisan test
```

Pin the main test job to production's PHP version too, and run Pint and Larastan in CI when the repo has them.

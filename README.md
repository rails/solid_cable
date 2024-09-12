# Solid Cable

Solid Cable is a database-backed Action Cable adapter that keeps messages in a table and continously polls for updates. This makes it possible to drop the common dependency on Redis, if it isn't needed for any other purpose. Despite polling, the performance of Solid Cable is comparable to Redis in most situations. And in all circumstances, it makes it easier to deploy Rails when Redis is no longer a required dependency for Action Cable functionality.


## Installation

Solid Cable is configured by default in new Rails 8 applications. But if you're running an earlier version, you can add it manually following these steps:

1. `bundle add solid_cable`
2. `bin/rails solid_cable:install`

This will configure Solid Cable as the production cable adapter by overwritting `config/cable.yml` and create `db/cable_schema.rb`.

You will then have to add the configuration for the cable database in `config/database.yml`. If you're using SQLite, it'll look like this:

```yaml
production:
  primary:
    <<: *default
    database: storage/production.sqlite3
  cable:
    <<: *default
    database: storage/production_cable.sqlite3
    migrations_paths: db/cable_migrate
```

...or if you're using MySQL/PostgreSQL/Trilogy:

```yaml
production:
  primary: &primary_production
    <<: *default
    database: app_production
    username: app
    password: <%= ENV["APP_DATABASE_PASSWORD"] %>
  cable:
    <<: *primary_production
    database: app_production_cable
    migrations_paths: db/cable_migrate
```

> [!NOTE]
> Calling `bin/rails solid_cable:install` will automatically setup `config/cable.yml`, so no additional configuration is needed there (although you must make sure that you use the `cable` name in `database.yml` for this to match!). But if you want to use Solid Cable in a different environment (like staging or even development), you'll have to manually add that `connects_to` block to the respective environment in the `config/cable.yml` file. And, as always, make sure that the name you're using for the database in `config/cable.yml` matches the name you define in `config/database.yml`.

Then run `db:prepare` in production to ensure the database is created and the schema is loaded.

## Configuration

All configuration is managed via the `config/cable.yml` file. By default, it'll be configured like this:

```yaml
production:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable
  polling_interval: 0.1.seconds
  message_retention: 1.day
```

The options are:

- `connects_to` - set the Active Record database configuration for the Solid Cable models. All options available in Active Record can be used here.
- `polling_interval` - sets the frequency of the polling interval. (Defaults to
  0.1.seconds)
- `message_retention` - sets the retention time for messages kept in the database. Used as the cut-off when trimming is performed. (Defaults to 1.day)
- `autotrim` - sets wether you want Solid Cable to handle autotrimming messages. (Defaults to true)
- `silence_polling` - whether to silence Active Record logs emitted when polling (Defaults to true)

## Trimming

Messages are autotrimmed based upon the `message_retention` setting to determine how long messages are to be kept around. If no `message_retention` is given or parsing fails, it defaults to `1.day`. Messages are trimmed when a subscriber unsubscribes.

Autotrimming can negatively impact performance depending on your workload because it is doing a delete on ubsubscribe. If
you would prefer, you can disable autotrimming by setting `autotrim: false` and you can manually enqueue the job later, `SolidCable::TrimJob.perform_later`, or run it on a recurring interval out of band.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

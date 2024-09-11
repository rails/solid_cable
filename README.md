# SolidCable

Solid Cable is a DB-based backend for Action Cable.


## Installation
Add this line to your application's Gemfile:

```ruby
gem "solid_cable"
```

And then execute:
```bash
$ bundle
```

Or install it yourself as:
```bash
$ gem install solid_cable
```

Now, you need to run the installer:

```bash
$ bin/rails generate solid_cable:install
```

This will create the `db/cable_schema.rb` file.

You will then have to add the configuration for the database in `config/database.yml`. If you're using SQLite, it'll look something like this:

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
> Calling `bin/rails generate solid_cable:install` will automatically setup `config/cable.yml`, so no additional configuration is needed there (although you must make sure that you use the `cable` name in `database.yml` for this to match!). But if you want to use Solid Cable in a different environment (like staging or even development), you'll have to manually add that `connects_to` block to the respective environment in the `config/cable.yml` file. And, as always, make sure that the name you're using for the database in `config/cable.yml` matches the name you define in `config/database.yml`.

Then run `db:prepare` in production to ensure the database is created and the schema is loaded.

## Usage

By default messages are kept around forever. SolidCable ships with a job to
prune messages. You can run `SolidCable::PruneJob.perform_later` which removes
Messages that are older than what is specified in `keep_messages_around_for`
setting.

## Configuration

All configuration is managed via the `config/cable.yml`file. To use Solid Cable, the `adapter` value *must be* `solid_cable`. When using Solid Cable, the other values you can set are: `connects_to`, `polling_interval`, `silence_polling`, and `keep_messages_around_for`. For example:

```yaml
production:
  adapter: solid_cable
  connects_to:
    database:
      writing: cable
  polling_interval: 0.1.seconds
  keep_messages_around_for: 1.day
```

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

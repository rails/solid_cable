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

Now, you need to install the necessary migrations and configure Action Cable's adapter.

```bash
$ bin/rails generate solid_cable:install
```

If you want to install to a different database you can pass an env variable.
```bash
$ DATABASE=cable bin/rails generate solid_cable:install
```

Update `config/cable.yml` to use the new adapter. connects_to is can be omitted
if you want to use the primary database.

```yaml
default: &default
  adapter: solid_cable
  polling_interval: 1.second
  keep_messages_around_for: 1.day

development:
  <<: *default
  silence_polling: true
  connects_to:
    database:
      writing: solid_cable_primary
      reading: solid_cable_replica

test:
  adapter: test

production:
  <<: *default
  polling_interval: 0.1.seconds
```

Finally, you need to run the migrations:

```bash
$ bin/rails db:migrate
```

By default messages are kept around forever. SolidCable ships with a job to
prune messages. You can run `SolidCable::PruneJob.perform_later` which removes
Messages that are older than what is specified in `keep_messages_around_for`
setting.

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

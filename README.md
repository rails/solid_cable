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
development:
  adapter: solid_cable
  silence_polling: true
  polling_interval: 1.second
  keep_messages_around_for: 30.minutes
  connects_to:
    database:
      writing: solid_cable_primary
      reading: solid_cable_replica

test:
  adapter: test

production:
  adapter: solid_cable
  polling_interval: 0.1.seconds
  keep_messages_around_for: 10.minutes
```

Finally, you need to run the migrations:

```bash
$ bin/rails db:migrate
```

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

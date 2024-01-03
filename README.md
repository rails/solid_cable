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

Now, you need to install the necessary migrations and configure the Action Cable's adapter.

```bash
$ bin/rails generate solid_cable:install
```

Update `config/cable.yml` to use the new adapter:

```yaml
development:
  adapter: solid_cable

test:
  adapter: test

production:
  adapter: solid_cable
```

Finally, you need to run the migrations:

```bash
$ bin/rails db:migrate
```

## License
The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

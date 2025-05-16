# Solid Cable

Solid Cable is a database-backed Action Cable adapter that keeps messages in a table and continuously polls for updates. This makes it possible to drop the common dependency on Redis, if it isn't needed for any other purpose. Despite polling, the performance of Solid Cable is comparable to Redis in most situations. And in all circumstances, it makes it easier to deploy Rails when Redis is no longer a required dependency for Action Cable functionality.

> [!NOTE]
> Solid Cable is tested to work with MySQL, SQLite, and PostgreSQL.
>
> Action Cable already has a [dedicated PostgreSQL adapter](https://guides.rubyonrails.org/action_cable_overview.html#postgresql-adapter),
> which utilizes the builtin `NOTIFY` command for better performance. However, that
> adapter has an 8kb limit on its payload. Solid Cable is a great alternative if you find yourself
> broadcasting large payloads, or prefer not to use the `NOTIFY` command.

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

### Single database configuration

Running Solid Cable in a separate database is recommended, but it's also possible to use a single database for both the app and Action Cable.

1. Copy the contents of `db/cable_schema.rb` into a normal migration and delete `db/cable_schema.rb`
2. Remove `connects_to` from `config/cable.yml`
3. `bin/rails db:migrate`

You won't have multiple databases, so `database.yml` doesn't need to have primary and cable database.

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
- `use_skip_locked` - whether to use `FOR UPDATE SKIP LOCKED` when performing trimming. This will be automatically detected in the future, and for now, you'd only need to set this to `false` if your database doesn't support it. For MySQL, that'd be versions < 8, and for PostgreSQL, versions < 9.5. If you use SQLite, this has no effect, as writes are sequential. (Defaults to true)
- `trim_batch_size` - the batch size to use when deleting old records (default: `100`)


## Trimming

Messages are autotrimmed based upon the `message_retention` setting to determine how long messages are to be kept around. If no `message_retention` is given or parsing fails, it defaults to `1.day`. Messages are trimmed when a messsage is broadcast.

Autotrimming can negatively impact performance slightly depending on your workload because it is potentially doing a delete on broadcast. If
you would prefer, you can disable autotrimming by setting `autotrim: false` and you can manually enqueue the job later, `SolidCable::TrimJob.perform_later`, or run it on a recurring interval out of band.


## Upgrading

If you have already installed Solid Cable < 3 and are upgrading to version 3,
run `solid_cable:update` to install a new migration.


## Benchmarks

Inside the `bench` directory there is a minimal Rails app that is used to benchmark.
You are welcome to update the config/deploy.yml file to point to your own server
if you want to deploy the app to your own server and run benchmarks.

To benchmark we use [k6](https://k6.io). Most of the setup was gotten from this
[article](https://evilmartians.com/chronicles/real-time-stress-anycable-k6-websockets-and-yabeda).
1. Install k6
1. Install xk6-cable by running `xk6 build --with
   github.com/anycable/xk6-cable`. This will output a custom k6 binary.
1. Run the load test with `./k6 run loadtest.js`
    - This script takes a variety of ENV variables:
        - WS_URL: The url to send websocket connections
        - MAX: The number of virtual users to hit the server with
        - TIME: The duration of the load test
        - MESSAGES_NUM: The number of messages each VU will send to the server


#### Results

Our loadtest is run on a Hetzner CCX13, with a MESSAGES_NUM of 5, and a TIME of 90.

##### SQLite

With a polling interval of 0.1 seconds and autotrimming enabled.

100 VUs
```
rtt..................: avg=135.82ms min=50ms     med=138ms    max=357ms    p(90)=174ms    p(95)=195ms
ws_connecting........: avg=205.81ms min=149.35ms med=199.01ms max=509.48ms p(90)=254.04ms p(95)=261.77ms
```
250 VUs
```
rtt..................: avg=146.24ms min=50ms     med=144ms    max=435ms p(90)=209ms   p(95)=234.04ms
ws_connecting........: avg=222.15ms min=146.47ms med=208.57ms max=1.3s  p(90)=263.6ms p(95)=284.18ms
```
500 VUs
```
rtt..................: avg=271.79ms min=48ms     med=205ms    max=1.15s p(90)=558ms    p(95)=660ms
ws_connecting........: avg=248.81ms min=145.89ms med=221.89ms max=1.38s p(90)=290.41ms p(95)=322.2ms
```
750 VUs
```
rtt..................: avg=548.27ms min=51ms     med=438ms    max=5.19s  p(90)=1.18s  p(95)=1.29s
ws_connecting........: avg=266.37ms min=144.06ms med=224.93ms max=2.33s  p(90)=298ms  p(95)=342.87ms
```

With trimming disabled

250 VUs
```
rtt..................: avg=139.47ms min=48ms     med=142ms    max=807ms p(90)=189ms    p(95)=214ms
ws_connecting........: avg=212.58ms min=146.19ms med=196.25ms max=1.25s p(90)=255.74ms p(95)=272.44ms
```

With a polling interval of 0.01 seconds it becomes comparable to Redis

250 VUs
```
rtt..................: avg=84.22ms  min=43ms     med=69ms     max=416ms p(90)=137ms    p(95)=150ms
ws_connecting........: avg=219.37ms min=144.71ms med=200.77ms max=2.17s p(90)=265.23ms p(95)=290.83ms
```

##### Redis

This instance was hosted on the same machine.

100 VUs
```
rtt..................: avg=68.95ms  min=41ms     med=56ms     max=6.23s  p(90)=114ms   p(95)=129ms
ws_connecting........: avg=211.09ms min=153.23ms med=195.69ms max=1.44s  p(90)=258.1ms p(95)=272.23ms
```
250 VUs
```
rtt..................: avg=69.32ms  min=40ms     med=56ms     max=645ms p(90)=119ms    p(95)=135ms
ws_connecting........: avg=212.95ms min=142.92ms med=196.31ms max=1.25s p(90)=260.25ms p(95)=273.49ms
```
500 VUs
```
rtt..................: avg=87.5ms   min=40ms     med=67ms     max=839ms p(90)=149ms    p(95)=176ms
ws_connecting........: avg=242.62ms min=142.03ms med=213.76ms max=2.34s p(90)=291.25ms p(95)=324.04ms
```
750 VUs
```
rtt..................: avg=162.54ms min=39ms  med=123ms    max=2.26s p(90)=343.1ms  p(95)=438ms
ws_connecting........: avg=353.08ms min=143ms med=264.15ms max=2.73s p(90)=541.36ms p(95)=1.15s
```


##### MySQL

With a polling interval of 0.1 seconds and autotrimming enabled. This instance
was also hosted on the same machine.

100 VUs
```
rtt..................: avg=136.02ms min=51ms     med=137ms    max=877ms p(90)=168.1ms  p(95)=198ms
ws_connecting........: avg=207.76ms min=151.93ms med=196.74ms max=1.21s p(90)=249.91ms p(95)=260.37ms
```
250 VUs
```
rtt..................: avg=159.33ms min=51ms    med=149ms    max=559ms p(90)=236ms    p(95)=263ms
ws_connecting........: avg=232.38ms min=151.6ms med=218.09ms max=1.38s p(90)=287.99ms p(95)=324.6ms
```
500 VUs
```
rtt..................: avg=441.07ms min=51ms     med=312ms    max=2.29s  p(90)=931ms    p(95)=1.07s
ws_connecting........: avg=256.73ms min=152.23ms med=231.02ms max=2.31s  p(90)=305.69ms p(95)=340.83ms
```
750 VUs
```
rtt..................: avg=822.08ms min=51ms     med=732ms    max=5.05s  p(90)=1.76s    p(95)=1.97s
ws_connecting........: avg=278.08ms min=146.66ms med=236.35ms max=2.37s  p(90)=318.17ms p(95)=374.98ms
```


##### PostgreSQL with Solid Cable

With a polling interval of 0.1 seconds and autotrimming enabled. This instance
was also hosted on the same machine.

100 VUs
```
rtt..................: avg=137.45ms min=48ms     med=139ms    max=439ms    p(90)=179.1ms  p(95)=204ms
ws_connecting........: avg=207.13ms min=150.29ms med=197.76ms max=443.67ms p(90)=254.44ms p(95)=263.29ms
```
250 VUs
```
rtt..................: avg=151.63ms min=49ms     med=146ms    max=538ms p(90)=222ms    p(95)=248.04ms
ws_connecting........: avg=245.89ms min=147.18ms med=205.57ms max=30s   p(90)=265.08ms p(95)=281.15ms
```
500 VUs
```
rtt..................: avg=362.79ms min=50ms     med=249ms    max=1.21s p(90)=757ms    p(95)=844ms
ws_connecting........: avg=257.02ms min=146.13ms med=227.65ms max=2.39s p(90)=303.22ms p(95)=344.39ms
```


##### PostgreSQL with dedicated adapter

100 VUs
```
rtt..................: avg=69.76ms  min=41ms     med=57ms     max=622ms p(90)=116ms    p(95)=133ms
ws_connecting........: avg=210.97ms min=149.68ms med=196.06ms max=1.27s p(90)=259.67ms p(95)=273.17ms
```
250 VUs
```
rtt..................: avg=73.43ms  min=40ms     med=58ms     max=698ms p(90)=126ms    p(95)=141ms
ws_connecting........: avg=210.83ms min=143.01ms med=195.22ms max=1.27s p(90)=259.27ms p(95)=272.6ms
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

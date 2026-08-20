# syntax=docker/dockerfile:1

ARG RUBY_VERSION
FROM rubylang/ruby:$RUBY_VERSION-noble AS base

WORKDIR /rails

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    <<EOF
  apt-get update -qq
  apt-get install --no-install-recommends -y libjemalloc2 sqlite3
  ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so
  rm -rf /var/lib/apt/lists /var/cache/apt/archives
EOF

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so" \
    RUBYOPT="--enable-frozen-string-literal"


FROM base AS build

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libssl-dev libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY --link Gemfile Gemfile.lock ./
RUN --mount=type=cache,target=/usr/local/bundle/cache \
    <<EOF
  bundle install
  rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git
EOF

COPY --link . .

RUN <<EOF
  SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile
  rm -rf app/assets
EOF


FROM base

COPY --link --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --link --from=build /rails /rails

RUN <<EOF
  mkdir -p /data /rails/storage /hist
  chown -R ubuntu:ubuntu /data /hist /rails/db /rails/log /rails/storage /rails/tmp
EOF

USER ubuntu

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
VOLUME /data
VOLUME /hist
CMD ["./bin/thrust", "./bin/rails", "server"]

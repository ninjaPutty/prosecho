# syntax=docker/dockerfile:1
ARG RUBY_VERSION=3.4.7
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

WORKDIR /rails
ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=development:test

FROM base AS build
RUN apt-get update && apt-get install -y --no-install-recommends build-essential git libpq-dev && \
    rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf /usr/local/bundle/ruby/*/cache /usr/local/bundle/ruby/*/bundler/gems/*/.git

COPY . .
RUN SECRET_KEY_BASE_DUMMY=1 bin/rails assets:precompile

FROM base
RUN apt-get update && apt-get install -y --no-install-recommends libpq5 && \
    rm -rf /var/lib/apt/lists/* && \
    groupadd --system --gid 1000 rails && \
    useradd --uid 1000 --gid rails --home-dir /rails rails && \
    chown rails:rails /rails

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --chown=rails:rails --from=build /rails /rails
USER rails
EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0"]

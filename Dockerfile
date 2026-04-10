FROM ruby:3.4.9-slim AS base

ARG BUNDLE_WITHOUT=development:test

ENV APP_HOME=/app \
    BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_WITHOUT=${BUNDLE_WITHOUT} \
    RAILS_LOG_TO_STDOUT=true \
    RAILS_SERVE_STATIC_FILES=true

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      chromium \
      chromium-driver \
      curl \
      git \
      imagemagick \
      libpq-dev \
      libyaml-dev \
      libvips \
      pkg-config \
      shared-mime-info \
      tesseract-ocr && \
    rm -rf /var/lib/apt/lists/*

WORKDIR $APP_HOME

COPY Gemfile Gemfile.lock* ./
RUN bundle config set without "$(printf '%s' "$BUNDLE_WITHOUT" | tr ':' ' ')" && \
    bundle install && \
    rm -rf /usr/local/bundle/cache/*.gem

COPY . .
RUN chmod +x bin/dev bin/docker-entrypoint bin/rails bin/setup
RUN RAILS_ENV=production \
    SECRET_KEY_BASE_DUMMY=1 \
    DATABASE_URL=postgres://postgres:postgres@postgres:5432/inkcreate_production \
    REDIS_URL=redis://redis:6379/0 \
    ACTIVE_STORAGE_SERVICE=local \
    bundle exec rails assets:precompile

EXPOSE 8080

ENTRYPOINT ["bin/docker-entrypoint"]
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]

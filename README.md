# Inkcreate

Inkcreate is a mobile-first notebook OCR companion app built as a Rails modular monolith and deployed on Google Cloud Run.

The production architecture and implementation plan live in [docs/architecture.md](/Users/achalindiresh/workspace/inkcreate/docs/architecture.md). The repository is intentionally scaffolded around:

- Rails API-first backend
- Cookie-based session auth with Devise on a same-origin PWA
- Direct browser uploads to Google Cloud Storage with signed URLs
- Background OCR and Drive export jobs via Cloud Tasks in production, with a Sidekiq-compatible fallback for local development
- PostgreSQL as the source of truth
- Redis for caching and local async execution

## Quick start

1. Install Ruby `3.4.9`, PostgreSQL, Redis, Tesseract, and ImageMagick.
2. Copy `.env.example` to `.env` and fill in local secrets.
3. Run `bundle install`.
4. Create the database and seed page templates:

```bash
bundle exec rails db:create db:migrate db:seed
```

5. Start the API and local async fallback worker in separate terminals:

```bash
bundle exec rails server
bundle exec sidekiq -C config/sidekiq.yml
```

## Web Push Setup

Reminder notifications need a VAPID keypair. Generate one once per environment:

```bash
ruby bin/generate_vapid_keys
```

Add `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, and `VAPID_SUBJECT` to `.env` for local development, or store the same values in your deployment secret manager. You can also store them in Rails credentials under `vapid.public_key`, `vapid.private_key`, and `vapid.subject`.

Keep the same keypair for a given environment after users subscribe, otherwise existing device subscriptions may stop working until they re-enable notifications.

On Cloud Run production, reminders now use scheduled Cloud Tasks from `CLOUD_TASKS_REMINDERS_QUEUE`. You do not need a separate Cloud Scheduler cron just to fire reminder notifications.

## Docker Compose deploy

1. Create runtime env:

```bash
cp .env.docker.example .env
```

Docker Compose now reads `DOCKER_DATABASE_URL` and `DOCKER_REDIS_URL` so your regular local `DATABASE_URL=...localhost...` settings do not leak into containers.
The app services also load `.env` directly, so values like `SECRET_KEY_BASE` are available at runtime.

2. Build image:

```bash
docker compose build
```

3. Run database setup/migrations:

```bash
docker compose --profile ops run --rm migrate
```

4. Start API + worker + dependencies:

```bash
docker compose up -d web worker postgres redis
```

When running in development, the `web` service now bind-mounts the app source so ERB, Ruby, JS, and the in-app workspace CSS update without rebuilding the image. Tailwind source changes are also watched inside the container. A normal browser refresh should pick up most changes.
The Compose build also includes development gems by default for local work. If you want the slimmer production-style image again, set `BUNDLE_WITHOUT=development:test` before building.

5. Verify services:

```bash
docker compose ps
docker compose logs -f web worker
```

App will be reachable on `http://localhost:8080`.

## Cloud Run note

For Cloud Run, continue using the single image in [Dockerfile](/Users/achalindiresh/workspace/inkcreate/Dockerfile). You can deploy either with the GitHub workflow in [.github/workflows/deploy.yml](/Users/achalindiresh/workspace/inkcreate/.github/workflows/deploy.yml) or with the Cloud Build pipeline in [cloudbuild.yaml](/Users/achalindiresh/workspace/inkcreate/cloudbuild.yaml). `docker-compose.yml` is for local/staging or VM-style deployments where you run all services together.

For the production IAM, Secret Manager, Cloud Tasks, and trigger-substitution setup, see [docs/cloud-run-setup.md](/Users/achalindiresh/workspace/inkcreate/docs/cloud-run-setup.md).

## Repository shape

- `app/controllers/api/v1` JSON API endpoints
- `app/services` service layer and provider abstractions
- `app/jobs` async OCR and Drive export jobs
- `app/models` domain entities kept intentionally slim
- `public/manifest.json` and `public/service-worker.js` PWA assets
- `docs/architecture.md` production architecture, flows, and rollout plan

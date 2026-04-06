# Cloud Run Setup

This guide documents the Google Cloud setup required for [cloudbuild.yaml](/Users/achalindiresh/workspace/inkcreate/cloudbuild.yaml).

Inkcreate can run in either of these modes:

- **Single-service mode**
  - one public Cloud Run service handles both web/API traffic and internal task callbacks
  - one migration job handles `db:migrate`
- **Split-service mode**
  - one public API service handles web/API traffic
  - one private worker service handles OCR and Drive export callbacks
  - one migration job handles `db:migrate`

If you are using only one service for now, keep `_API_SERVICE` and `_WORKER_SERVICE` set to the same Cloud Run service name, for example `inkcreate-git`.

## Single-service mode

Use this when you want the simplest possible first deployment.

Cloud Build trigger substitutions:

- `_API_SERVICE=inkcreate-git`
- `_WORKER_SERVICE=inkcreate-git`
- `_CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL=` left blank

Behavior in this mode:

- Cloud Tasks callbacks go back to the same public service URL
- you do **not** need a separate worker Cloud Run service
- you do **not** need to grant `Cloud Run Invoker` on a separate worker service
- the runtime service account and Secret Manager setup are still required

Tradeoff:

- background OCR/export traffic shares the same Cloud Run service as user traffic
- this is simpler to operate, but less isolated than split-service mode

## Split-service mode

Use this when you want cleaner production isolation between user traffic and background processing.

Typical substitutions:

- `_API_SERVICE=inkcreate-api`
- `_WORKER_SERVICE=inkcreate-worker`
- `_CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL=inkcreate-tasks-invoker@thoughtbasics.iam.gserviceaccount.com`

## 1. Enable required APIs

```bash
PROJECT_ID=thoughtbasics

gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  cloudtasks.googleapis.com \
  iamcredentials.googleapis.com \
  storage.googleapis.com \
  --project=$PROJECT_ID
```

## 2. Create service accounts

Always create one runtime identity for the Cloud Run containers.

Create the Cloud Tasks invoker identity only if you are using split-service mode with a private worker service.

```bash
PROJECT_ID=thoughtbasics
RUNTIME_SA=inkcreate-runtime
TASKS_SA=inkcreate-tasks-invoker

gcloud iam service-accounts create $RUNTIME_SA \
  --project=$PROJECT_ID \
  --display-name="Inkcreate Cloud Run runtime"

gcloud iam service-accounts create $TASKS_SA \
  --project=$PROJECT_ID \
  --display-name="Inkcreate Cloud Tasks invoker"
```

The resulting emails will look like:

- `inkcreate-runtime@thoughtbasics.iam.gserviceaccount.com`
- `inkcreate-tasks-invoker@thoughtbasics.iam.gserviceaccount.com` (split-service mode only)

## 3. Grant roles to the runtime service account

Inkcreate needs the runtime service account to:

- enqueue Cloud Tasks
- read secrets from Secret Manager
- read uploaded objects from Cloud Storage
- create signed upload/download URLs using `signBlob`

These commands grant the minimum roles used by the current app flow.

```bash
PROJECT_ID=thoughtbasics
BUCKET=inkcreate-uploads
RUNTIME_EMAIL="inkcreate-runtime@${PROJECT_ID}.iam.gserviceaccount.com"
```

### Project-level role for Cloud Tasks enqueue

```bash
gcloud projects add-iam-policy-binding $PROJECT_ID \
  --member="serviceAccount:${RUNTIME_EMAIL}" \
  --role="roles/cloudtasks.enqueuer"
```

### Bucket-level roles for signed upload/download flows

Inkcreate issues signed URLs for uploads and also downloads existing objects for preview, OCR, and Drive export.

```bash
gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member="serviceAccount:${RUNTIME_EMAIL}" \
  --role="roles/storage.objectViewer"

gcloud storage buckets add-iam-policy-binding gs://$BUCKET \
  --member="serviceAccount:${RUNTIME_EMAIL}" \
  --role="roles/storage.objectCreator"
```

If you prefer a simpler single bucket role, you can replace those two grants with `roles/storage.objectAdmin`.

### Allow the runtime service account to sign blobs as itself

Inkcreate uses Cloud Storage signed URLs. Google’s signed URL guidance requires blob-signing permission (`iam.serviceAccounts.signBlob`), which is included in `roles/iam.serviceAccountTokenCreator`.

```bash
gcloud iam service-accounts add-iam-policy-binding $RUNTIME_EMAIL \
  --member="serviceAccount:${RUNTIME_EMAIL}" \
  --role="roles/iam.serviceAccountTokenCreator"
```

## 4. Grant Cloud Tasks permission to invoke the worker service

Skip this section entirely in single-service mode.

Cloud Tasks should call the private `inkcreate-worker` service, not the public API service.

```bash
PROJECT_ID=thoughtbasics
REGION=asia-south1
TASKS_EMAIL="inkcreate-tasks-invoker@${PROJECT_ID}.iam.gserviceaccount.com"

gcloud run services add-iam-policy-binding inkcreate-worker \
  --project=$PROJECT_ID \
  --region=$REGION \
  --member="serviceAccount:${TASKS_EMAIL}" \
  --role="roles/run.invoker"
```

Set `_CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL` in the Cloud Build trigger to this same service account email.

## 5. Create Secret Manager secrets

The current [cloudbuild.yaml](/Users/achalindiresh/workspace/inkcreate/cloudbuild.yaml) expects these secret names:

- `inkcreate-database-url`
- `inkcreate-secret-key-base`
- `inkcreate-google-oauth-client-id`
- `inkcreate-google-oauth-client-secret`
- `inkcreate-active-record-encryption-primary-key`
- `inkcreate-active-record-encryption-deterministic-key`
- `inkcreate-active-record-encryption-key-derivation-salt`
- `inkcreate-internal-task-token`
- optional: `inkcreate-sentry-dsn`

Create them once:

```bash
PROJECT_ID=thoughtbasics

for SECRET in \
  inkcreate-database-url \
  inkcreate-secret-key-base \
  inkcreate-google-oauth-client-id \
  inkcreate-google-oauth-client-secret \
  inkcreate-active-record-encryption-primary-key \
  inkcreate-active-record-encryption-deterministic-key \
  inkcreate-active-record-encryption-key-derivation-salt \
  inkcreate-internal-task-token
do
  gcloud secrets create "$SECRET" \
    --project=$PROJECT_ID \
    --replication-policy=automatic || true
done
```

Add secret values:

```bash
printf '%s' 'postgresql://...' | gcloud secrets versions add inkcreate-database-url --project=$PROJECT_ID --data-file=-
printf '%s' 'your-secret-key-base' | gcloud secrets versions add inkcreate-secret-key-base --project=$PROJECT_ID --data-file=-
printf '%s' 'your-google-oauth-client-id.apps.googleusercontent.com' | gcloud secrets versions add inkcreate-google-oauth-client-id --project=$PROJECT_ID --data-file=-
printf '%s' 'your-google-oauth-client-secret' | gcloud secrets versions add inkcreate-google-oauth-client-secret --project=$PROJECT_ID --data-file=-
printf '%s' 'your-active-record-encryption-primary-key' | gcloud secrets versions add inkcreate-active-record-encryption-primary-key --project=$PROJECT_ID --data-file=-
printf '%s' 'your-active-record-encryption-deterministic-key' | gcloud secrets versions add inkcreate-active-record-encryption-deterministic-key --project=$PROJECT_ID --data-file=-
printf '%s' 'your-active-record-encryption-key-derivation-salt' | gcloud secrets versions add inkcreate-active-record-encryption-key-derivation-salt --project=$PROJECT_ID --data-file=-
printf '%s' 'replace-with-random-internal-task-token' | gcloud secrets versions add inkcreate-internal-task-token --project=$PROJECT_ID --data-file=-
```

Generate the three Active Record encryption values once with Rails:

```bash
bin/rails db:encryption:init
```

Use the printed values for:

- `ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY`
- `ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY`
- `ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT`

### Allow the runtime service account to read the secrets

```bash
PROJECT_ID=thoughtbasics
RUNTIME_EMAIL="inkcreate-runtime@${PROJECT_ID}.iam.gserviceaccount.com"

for SECRET in \
  inkcreate-database-url \
  inkcreate-secret-key-base \
  inkcreate-google-oauth-client-id \
  inkcreate-google-oauth-client-secret \
  inkcreate-active-record-encryption-primary-key \
  inkcreate-active-record-encryption-deterministic-key \
  inkcreate-active-record-encryption-key-derivation-salt \
  inkcreate-internal-task-token
do
  gcloud secrets add-iam-policy-binding "$SECRET" \
    --project=$PROJECT_ID \
    --member="serviceAccount:${RUNTIME_EMAIL}" \
    --role="roles/secretmanager.secretAccessor"
done
```

If you also use Sentry:

```bash
gcloud secrets add-iam-policy-binding inkcreate-sentry-dsn \
  --project=$PROJECT_ID \
  --member="serviceAccount:${RUNTIME_EMAIL}" \
  --role="roles/secretmanager.secretAccessor"
```

## 6. Configure Cloud Build trigger substitutions

The main substitutions to set or confirm are:

- `_RUNTIME_SERVICE_ACCOUNT=inkcreate-runtime@thoughtbasics.iam.gserviceaccount.com`
- `_APP_URL=https://inkcreate.thoughtbasics.com`
- `_GOOGLE_DRIVE_REDIRECT_URI=https://inkcreate.thoughtbasics.com/api/v1/drive_connection/callback`
- `_DEPLOY_REGION=asia-south1`
- `_GCS_UPLOAD_BUCKET=inkcreate-uploads`

Then choose one of these service layouts:

### Single-service mode

- `_API_SERVICE=inkcreate-git`
- `_WORKER_SERVICE=inkcreate-git`
- `_CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL=` blank

### Split-service mode

- `_API_SERVICE=inkcreate-api`
- `_WORKER_SERVICE=inkcreate-worker`
- `_CLOUD_TASKS_SERVICE_ACCOUNT_EMAIL=inkcreate-tasks-invoker@thoughtbasics.iam.gserviceaccount.com`

The secret-name substitutions should usually stay at their defaults unless you rename the secrets:

- `_DATABASE_URL_SECRET=inkcreate-database-url`
- `_SECRET_KEY_BASE_SECRET=inkcreate-secret-key-base`
- `_GOOGLE_OAUTH_CLIENT_ID_SECRET=inkcreate-google-oauth-client-id`
- `_GOOGLE_OAUTH_CLIENT_SECRET_SECRET=inkcreate-google-oauth-client-secret`
- `_ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY_SECRET=inkcreate-active-record-encryption-primary-key`
- `_ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY_SECRET=inkcreate-active-record-encryption-deterministic-key`
- `_ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT_SECRET=inkcreate-active-record-encryption-key-derivation-salt`
- `_INTERNAL_TASK_TOKEN_SECRET=inkcreate-internal-task-token`

## 7. Notes

- Single-service mode is acceptable for early deployment simplicity.
- Keep the API and worker services separate if you want background OCR/export traffic isolated from user-facing web requests.
- If you rotate any secret, add a new Secret Manager version; the pipeline reads `latest`.
- If browser uploads start failing with signed URL permission errors, double-check the runtime service account’s Cloud Storage roles and `iam.serviceAccounts.signBlob` access.

## References

These Google Cloud docs are the basis for the IAM guidance above:

- [Cloud Storage signed URLs](https://cloud.google.com/storage/docs/access-control/signed-urls)
- [Create signatures with signBlob](https://cloud.google.com/storage/docs/authentication/creating-signatures)
- [V4 signing with Cloud Storage tools](https://cloud.google.com/storage/docs/access-control/signing-urls-with-helpers)
- [Cloud Run secrets configuration](https://cloud.google.com/run/docs/configuring/services/secrets)

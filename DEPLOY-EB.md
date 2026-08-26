# Deploying the LexDocs backend to AWS Elastic Beanstalk

The backend deploys to the Elastic Beanstalk **Docker** platform. EB builds the
`Dockerfile` on the instance and puts nginx in front of the container.

The bundle is built from the **contents of `backend/`**, because EB requires
`Dockerfile` and `Dockerrun.aws.json` at the root of the archive.

---

## 1. Provision the AWS dependencies first

The app fails fast at startup if Postgres or `GEMINI_API_KEY` are missing, so
set these up before the first deploy.

| Dependency | What to use | Notes |
|---|---|---|
| **PostgreSQL** | RDS Postgres (`db.t4g.micro` is enough to start) | Required. Schema is auto-migrated by GORM on boot — no manual migration step. |
| **Qdrant** | Qdrant Cloud free tier | Optional. Without it, semantic search/RAG is disabled but the app still boots. |
| **Redis** | — | Optional and currently stubbed out; safe to skip. |

Put RDS in the **same VPC** as the EB environment, and allow inbound `5432`
from the EB instance's security group.

## 2. Set environment properties (secrets)

Non-secret config already ships in [.ebextensions/01-environment.config](backend/.ebextensions/01-environment.config).
Secrets must never go in the bundle — set them on the environment:

```bash
eb setenv \
  POSTGRES_HOST=<rds-endpoint> \
  POSTGRES_PORT=5432 \
  POSTGRES_USER=docassist \
  POSTGRES_PASSWORD=<password> \
  POSTGRES_DB=docassist_db \
  JWT_ACCESS_SECRET=<openssl rand -base64 32> \
  JWT_REFRESH_SECRET=<openssl rand -base64 32> \
  JWT_ACCESS_EXPIRY=24h \
  JWT_REFRESH_EXPIRY=168h \
  GEMINI_API_KEY=<key> \
  OPENAI_API_KEY=<key> \
  GROQ_API_KEY=<key> \
  QDRANT_HOST=<host> \
  QDRANT_API_KEY=<key>
```

Or in the console: **Configuration → Updates, monitoring, and logging →
Environment properties**.

**Required** — the app calls `log.Fatal` and the deploy fails without them:
`JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `GEMINI_API_KEY`, plus working
Postgres credentials.

## 3. Build the bundle

```powershell
powershell -ExecutionPolicy Bypass -File scripts\build-eb-bundle.ps1
```

Produces `dist/lexdocs-backend-eb.zip` with `Dockerfile`, `Dockerrun.aws.json`,
`.ebextensions/`, and `.platform/` at the archive root, and with `.env`,
`storage/`, `logs/`, and test fixtures excluded.

## 4. Deploy

**Console:** Create application → Platform **Docker** → *Upload your code* →
upload `dist/lexdocs-backend-eb.zip`.

**EB CLI** (run from inside `backend/`, so the bundle root is correct — the CLI
reads [.ebignore](backend/.ebignore) and zips for you):

```bash
cd backend
eb init -p docker lexdocs-api --region ap-south-1
eb create lexdocs-api-prod --single --instance-type t3.small
eb deploy
```

`--single` creates a single-instance environment (no load balancer, no hourly
ALB cost). See "Single-instance vs load-balanced" below.

Verify:

```bash
curl https://<env>.elasticbeanstalk.com/health
# {"status":"healthy","services":{"database":true,...}}
```

---

## Single-instance vs load-balanced

Shipped defaults target a **single-instance** environment.

If you create a **load-balanced** environment instead, rename
`.ebextensions/03-loadbalancer.config.example` → `.03-loadbalancer.config`
(drop the `.example`). It raises the ALB idle timeout to 300s and points the
target-group health check at `/health`. Without it, the ALB's default **60s
idle timeout** cuts off long AI/OCR requests regardless of the app's own limits.

Do **not** enable that file on a single-instance environment — there is no load
balancer and EB rejects the deploy with `Invalid option specification`.

---

## Changes made to make this deployable

Fixes applied on top of the previous (Render-targeted) setup:

**[backend/Dockerfile](backend/Dockerfile)**
- `go.mod` requires **Go 1.25.8** but the image pinned `golang:1.22`. The build
  only worked because `GOTOOLCHAIN=auto` re-downloaded the toolchain on every
  build — slow, and a hard failure on a network-restricted instance. Now pinned
  to `golang:1.25-bookworm`.
- **Dropped CGO.** The Dockerfile installed `libtesseract-dev` +
  `libleptonica-dev` and built with `CGO_ENABLED=1` "for gosseract" — but
  gosseract is not in `go.mod`. The OCR layer shells out to the `tesseract` and
  `pdftoppm` binaries ([pkg/ocr/tesseract.go](backend/pkg/ocr/tesseract.go)).
  The binary is now fully static, which cuts build time and memory on the EB
  instance and decouples builder from runtime glibc.
- `wget` → `curl` for the healthcheck and tessdata fetch.
- **The Modi script OCR download never worked.** The image fetched
  `mod.traineddata` from the Tesseract repo, but upstream Tesseract publishes no
  Modi model — that URL 404s in every tessdata repo. The step ended in
  `|| echo "WARN: ..."`, so the 404 was swallowed and every image shipped
  without it. (The Go side degrades gracefully: `ocrImageFile` retries with
  `+mod` stripped, so this showed up as slower OCR, not an error.) Replaced with
  the **Devanagari** script model, which does exist and covers
  Marathi/Hindi/Sanskrit — and the step now fails the build instead of
  swallowing the error, since the silent skip is what hid this for so long.
  Verified in the built image: `tesseract --list-langs` → `Devanagari, eng, hin,
  mar, osd, san`.

**[backend/cmd/server/main.go](backend/cmd/server/main.go)**
- The log directory was derived by *slicing* the path string
  (`FilePath[:len(FilePath)-len("/app.log")]`). It panics for any
  `LOG_FILE_PATH` shorter than 8 characters and silently makes a wrong
  directory for any filename other than `app.log`. Now `filepath.Dir`.
- Startup printed the full Postgres **DSN, including the password**, to stdout —
  which on EB streams into CloudWatch. Now logs host/db/sslmode only.

**New EB platform files**
- [Dockerrun.aws.json](backend/Dockerrun.aws.json) — maps nginx to container
  port 8080, and bind-mounts `/var/app/storage` + `/var/app/logs` from the host
  so uploads survive a redeploy.
- [.platform/nginx/conf.d/proxy.conf](backend/.platform/nginx/conf.d/proxy.conf) —
  **the most important file here.** EB's nginx defaults to a **1 MB** body limit
  and a **60s** proxy read timeout. Both reject the request before it ever
  reaches Go, so the app's own 500 MB upload limit and 300s `WriteTimeout` were
  unreachable: every upload over 1 MB would have returned **413**, and every
  document-summarize / complaint-reply call would have returned **504**.
- [.ebextensions/01-environment.config](backend/.ebextensions/01-environment.config) —
  instance type, 30 GB root volume, 1800s deploy timeout (a cold Docker build
  exceeds the 600s default), `/health` health check, log streaming, non-secret
  env vars.
- [.ebextensions/02-storage-permissions.config](backend/.ebextensions/02-storage-permissions.config) —
  chowns the host volumes to UID 1001. The container runs as non-root, and
  Docker creates bind-mount host dirs as root, so the first upload would have
  failed with a permission error.
- [.ebignore](backend/.ebignore) — keeps `backend/.env` (real secrets) out of
  the bundle.

---

## Known limitation: file storage is not durable

`STORAGE_TYPE=local` writes uploads to the instance's disk. The host volume
means they survive **redeploys**, but **not** instance replacement — and EB
replaces instances on scale-in, on immutable updates, and when it retires an
unhealthy instance. They are also not shared across instances, so uploads break
if you ever scale past one instance.

For production this should move to **S3** (add an `s3` implementation behind the
existing `STORAGE_TYPE` switch in
[config.go](backend/config/config.go), used at
[document_service.go:94](backend/internal/document/service/document_service.go#L94)).
EFS mounted via `.ebextensions` is the smaller-change alternative.

## Troubleshooting

| Symptom | Cause |
|---|---|
| Deploy times out mid-build | Instance too small. `t3.micro` OOMs during `go build`; use `t3.small`+. |
| `413 Request Entity Too Large` | `.platform/nginx/conf.d/proxy.conf` missing from the bundle. |
| `504` on AI endpoints | Same file missing, or ALB idle timeout on a load-balanced env (see above). |
| Health check red, `degraded` | App can't reach Postgres — check the RDS security group allows 5432 from the EB instance SG. |
| Container restart loop | A required env var is unset (`JWT_*_SECRET`, `GEMINI_API_KEY`). Check `eb logs`. |
| Permission denied writing uploads | `02-storage-permissions.config` didn't run; confirm the UID in it matches the Dockerfile's `useradd -u 1001`. |

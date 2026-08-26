# Deploying the LexDocs Flutter web app to CloudFront

## Architecture

One CloudFront distribution, two origins:

```
                    ┌─────────────────────────────┐
  browser ──HTTPS──►│  CloudFront distribution    │
                    │                             │
                    │  /api/*  ──HTTP──► Elastic Beanstalk backend
                    │  /*      ────────► S3 bucket (Flutter web build)
                    └─────────────────────────────┘
```

The S3 bucket is **private** — CloudFront reads it through an Origin Access
Control (OAC), and nothing is publicly readable.

### Why the API goes through CloudFront too

Not for performance — for correctness. CloudFront serves the page over HTTPS,
and **a browser blocks an HTTPS page from calling a plain `http://` endpoint**
(mixed content). The backend has no TLS certificate of its own, so a web build
pointed straight at it would load fine and then fail *every* API call.

Putting `/api/*` on the same distribution solves this: CloudFront terminates TLS
for the browser and talks plain HTTP to the backend on the AWS network. It also
makes the API same-origin, so CORS never applies.

This is why [dio_client.dart](flutter/docassist_app/lib/core/network/dio_client.dart)
derives its base URL from the page origin on web (`${Uri.base.origin}/api/v1`)
instead of the hardcoded `http://3.108.194.79:8080/api/v1` that native builds
still use. Native builds are unaffected — they have no origin to inherit and no
mixed-content rule.

---

## Prerequisite: the backend must be healthy first

The frontend will deploy and serve regardless, but every API call returns **502**
until the `/api/*` origin is healthy. See [DEPLOY-EB.md](DEPLOY-EB.md).

The origin must be the EB **CNAME**, not an IP:

```
Lexdocs-api-env.eba-bjjysxvm.ap-south-1.elasticbeanstalk.com
```

**CloudFront rejects raw IP addresses as origins**, so `3.108.194.79` (the
hand-deployed `myapp-server` EC2 instance the Flutter app currently points at)
cannot be used. That IP is also not an Elastic IP, so it changes whenever the
instance restarts. The script rejects an IP origin rather than failing later.

## Deploy

First time (creates bucket, OAC, distribution):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\deploy-web.ps1 -CreateInfra
```

Afterwards (build, upload, invalidate):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\deploy-web.ps1
```

Both are idempotent — the script finds existing infrastructure by matching the
S3 origin domain, so re-running never creates a duplicate distribution.

A new distribution takes **10–15 minutes** to reach `Deployed`:

```powershell
aws cloudfront get-distribution --id <ID> --query 'Distribution.Status' --output text
```

Point a different backend at it:

```powershell
.\scripts\deploy-web.ps1 -CreateInfra -ApiOrigin my-env.ap-south-1.elasticbeanstalk.com
```

---

## The 60-second cap on API responses

**This is the sharpest limitation of this architecture and it needs a decision.**

CloudFront's origin response timeout defaults to 30s and maxes at **60s**. Beyond
that it returns **504** to the browser. The ceiling can be raised to **180s** —
but no further — by requesting a quota increase for *"Response timeout per
origin"* under Service Quotas → CloudFront.

Your backend is built for much longer work:

| Layer | Timeout |
|---|---|
| Go server `WriteTimeout` ([main.go](backend/cmd/server/main.go)) | 300s |
| EB nginx `proxy_read_timeout` ([proxy.conf](backend/.platform/nginx/conf.d/proxy.conf)) | 300s |
| Flutter `receiveTimeout` ([dio_client.dart](flutter/docassist_app/lib/core/network/dio_client.dart)) | 600s |
| **CloudFront** | **60s (180s max)** |

So any AI or OCR call that runs past 60s — a large scanned PDF summarize, a long
`analyze` — will 504 **on web** while continuing to work on Android, which
bypasses CloudFront entirely. The script sets `OriginReadTimeout` to 60, the
highest value available without a quota request.

Ways to close the gap, roughly in order of effort:

1. **Request the quota increase to 180s.** Free, and covers most real documents
   given the 150-DPI/20-page OCR path. Does not help beyond 180s.
2. **Make long endpoints async.** `complaint-reply` already does this correctly —
   it returns a `job_id` and the client polls
   `/ai/complaint-reply/status/:job_id`, so no single request stays open. The
   same pattern applied to `summarize`, `analyze`, and `ask` removes the ceiling
   entirely. This is the real fix.
3. **Give the backend its own HTTPS endpoint** (ALB + ACM certificate on a domain
   you own) and point web traffic straight at it, bypassing CloudFront for the
   API. Costs ~$16–20/month for the ALB and needs a registered domain.

---

## Caching

Flutter's web output is **not content-hashed** — `main.dart.js` keeps its name
across builds. A long browser cache would strand users on stale code that a
CloudFront invalidation cannot reach (invalidation clears CloudFront, not
browsers). So:

| Files | Cache-Control |
|---|---|
| `index.html`, `main.dart.js`, `flutter_bootstrap.js`, assets | `max-age=0, must-revalidate` |
| `canvaskit/*` (versioned by the Flutter SDK) | `max-age=31536000, immutable` |

Revalidation is cheap — a 304 with no body — and every deploy issues an
invalidation of `/*` anyway. AWS gives 1,000 free invalidation paths per month;
`/*` counts as one path.

## Deep links

Flutter uses client-side routing, so a deep link like `/documents/123` is not an
S3 object and S3 answers 403/404. The distribution rewrites both to
`/index.html` with a **200**, letting `go_router` resolve the path. Without this,
every refresh on a sub-route shows an XML error page.

## Troubleshooting

| Symptom | Cause |
|---|---|
| All API calls 502 | Backend origin unhealthy — check EB environment health. |
| API calls 504 after ~60s | The origin response timeout above. |
| Blank page, console shows mixed-content block | App is using an absolute `http://` base URL. It should derive from `Uri.base.origin` on web. |
| 403 AccessDenied (XML) on every path | Bucket policy or OAC not attached — re-run with `-CreateInfra`. |
| Refresh on a sub-route 404s | `CustomErrorResponses` missing from the distribution. |
| Stale app after deploy | Invalidation didn't run, or a file got a long `max-age`. |

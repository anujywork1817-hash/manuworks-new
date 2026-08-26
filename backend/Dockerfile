# ─────────────────────────────────────────────────────────────────────────────
# Stage 1: Builder
#
# The OCR layer shells out to the `tesseract` / `pdftoppm` / `pdftotext`
# binaries (see pkg/ocr/tesseract.go) rather than linking libtesseract, so no
# CGO and no Tesseract headers are needed at compile time. That keeps the
# build fast enough to run on a small Elastic Beanstalk instance.
# ─────────────────────────────────────────────────────────────────────────────
FROM golang:1.25-bookworm AS builder

WORKDIR /app

# Copy dependency files first for better layer caching
COPY go.mod go.sum ./
RUN go mod download

# Copy all source code
COPY . .

# Fully static binary — no glibc coupling between builder and runtime.
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags="-s -w" \
    -trimpath \
    -o /app/docassist \
    ./cmd/server

# ─────────────────────────────────────────────────────────────────────────────
# Stage 2: Runtime
# Lean Debian image holding the OCR/PDF command-line tools the app invokes.
# ─────────────────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS runtime

RUN apt-get update && apt-get install -y --no-install-recommends \
    tesseract-ocr \
    tesseract-ocr-eng \
    tesseract-ocr-mar \
    tesseract-ocr-hin \
    tesseract-ocr-san \
    poppler-utils \
    ghostscript \
    ca-certificates \
    tzdata \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Devanagari script model — a script-level model that covers Marathi/Hindi/
# Sanskrit and is not shipped as a Debian package.
#
# This replaces an earlier `mod.traineddata` (Modi script) fetch. Upstream
# Tesseract publishes no Modi model — that URL 404s in every tessdata repo — and
# the old step ended in `|| echo WARN`, so the 404 was swallowed and the image
# shipped without it regardless. Deliberately NOT tolerant of failure here: a
# silent skip is what hid the previous bug. The build already requires network
# for apt, so failing loudly costs nothing.
RUN TESSDATA=$(find /usr/share/tesseract-ocr -name tessdata -type d | head -1) && \
    curl -fsSL -o "$TESSDATA/Devanagari.traineddata" \
    "https://github.com/tesseract-ocr/tessdata/raw/main/script/Devanagari.traineddata" && \
    test -s "$TESSDATA/Devanagari.traineddata"

# Non-root user. UID 1001 is hardcoded here because the Elastic Beanstalk
# predeploy hook chowns the mounted host directories to the same UID.
RUN groupadd -r docassist && useradd -r -g docassist -u 1001 docassist

RUN mkdir -p /app/storage /app/logs && chown -R docassist:docassist /app

WORKDIR /app

COPY --from=builder /app/docassist .

USER docassist

# Elastic Beanstalk's nginx proxy forwards to this port (see Dockerrun.aws.json).
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -fsS "http://localhost:${PORT:-8080}/health" || exit 1

ENTRYPOINT ["./docassist"]

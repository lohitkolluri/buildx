# syntax=docker/dockerfile:1

ARG GO_VERSION=1.26
ARG ALPINE_VERSION=3.23

ARG FORMATS=md,yaml

FROM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS docsgen
WORKDIR /src
RUN --mount=target=. \
  --mount=target=/root/.cache,type=cache \
  go build -mod=vendor -o /out/docsgen ./docs/generate.go

FROM alpine:${ALPINE_VERSION} AS gen
RUN apk add --no-cache rsync git
WORKDIR /src
COPY --from=docsgen /out/docsgen /usr/bin
ARG FORMATS
ARG BUILDX_EXPERIMENTAL
RUN --mount=target=/context \
  --mount=target=.,type=tmpfs <<EOT
set -e
rsync -a /context/. .
docsgen --formats "$FORMATS" --source "docs/reference/" --bake-stdlib-source "docs/bake-stdlib.md"
mkdir /out
cp -r docs/reference docs/bake-stdlib.md /out
rm -f /out/reference/*__INTERNAL_SERVE.yaml /out/reference/*__INTERNAL_SERVE.md
EOT

FROM scratch AS update
COPY --from=gen /out /out

FROM gen AS validate
RUN --mount=target=/context \
  --mount=target=.,type=tmpfs <<EOT
set -e
rsync -a /context/. .

# Replace checked-in docs with freshly generated output and ensure this does not
# leave the repository dirty, matching the contract of `make docs`.
rm -rf docs/reference
cp -r /out/reference docs/reference
cp /out/bake-stdlib.md docs/bake-stdlib.md

git add -A docs/reference docs/bake-stdlib.md
if ! git diff --cached --quiet; then
  echo >&2 'ERROR: Docs result differs. Please update with "make docs"'
  git diff --cached
  exit 1
fi
EOT

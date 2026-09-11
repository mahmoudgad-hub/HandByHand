# =====================================================================
# hbhd - the parent portal API
#
# Nothing is installed on the developer machine (D-9). The toolchain
# lives in the build stage and does not survive into the image that
# runs: the result is one static binary, a certificate bundle, and a
# user that is not root.
# =====================================================================

FROM golang:1.24-alpine AS build

WORKDIR /src

# Dependencies first, so a source edit does not re-download the module
# cache on every build.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# The unit tests run in the build. A binary that does not pass them is
# not worth producing, and finding that out at deploy time is worse.
RUN go vet ./... && go test ./...

# CGO off: a static binary needs nothing from the base image, so the
# runtime stage can stay this thin.
RUN CGO_ENABLED=0 GOOS=linux go build -trimpath -ldflags="-s -w" -o /out/hbhd ./cmd/hbhd

# ---------------------------------------------------------------------

FROM alpine:3.21

# ca-certificates only for the day this service calls an SMS gateway
# over TLS. The database connection inside the compose network does not
# need it, and adding it later is a rebuild nobody would think to make.
RUN apk add --no-cache ca-certificates tzdata \
 && adduser -D -u 10001 hbh

COPY --from=build /out/hbhd /usr/local/bin/hbhd

USER hbh
EXPOSE 8090

# UTC in the container as well as in the database. Every instant is
# stored and compared in UTC; local time is a display concern (D-5).
ENV TZ=UTC

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
  CMD wget -q -O - http://127.0.0.1:8090/healthz >/dev/null 2>&1 || exit 1

ENTRYPOINT ["/usr/local/bin/hbhd"]

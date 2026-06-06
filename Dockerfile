# Forked-build of nats-io/nats-server into a 4-arch openweft image
# (linux/amd64 + arm64 + riscv64 + loong64). Tracks upstream releases
# via the NATS_VERSION build-arg ; bump = one ARG change + a `vX.Y.Z`
# git tag here.

ARG NATS_VERSION=v2.11.0
ARG GO_VERSION=1.23

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-bookworm AS builder
ARG NATS_VERSION TARGETOS TARGETARCH
WORKDIR /src
RUN apt-get update && apt-get install -y --no-install-recommends git ca-certificates && rm -rf /var/lib/apt/lists/*
RUN git clone --depth=1 --branch=${NATS_VERSION} https://github.com/nats-io/nats-server.git .
ENV CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH}
RUN go build -trimpath -ldflags="-s -w" -o /out/nats-server .

FROM scratch
ARG NATS_VERSION
LABEL org.opencontainers.image.title="weft-nats" \
      org.opencontainers.image.description="openweft 4-arch build of nats-io/nats-server" \
      org.opencontainers.image.version="${NATS_VERSION}" \
      org.opencontainers.image.source="https://github.com/openweft/weft-nats" \
      org.opencontainers.image.url="https://github.com/openweft/weft-nats" \
      org.opencontainers.image.licenses="Apache-2.0"
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /out/nats-server /usr/local/bin/nats-server
EXPOSE 4222 6222 8222
ENTRYPOINT ["/usr/local/bin/nats-server"]

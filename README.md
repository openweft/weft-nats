# weft-nats

The NATS broker image of a [weft-loom-server](https://github.com/openweft/weft-loom-server)
deployment: `ghcr.io/openweft/weft-nats`, a 4-arch build (amd64, arm64, riscv64,
loong64) of nats-server. The image tag is the nats-server version it is built from.

The broker carries share credentials (`weft.mounts.<vmID>`), so it is closed by default:

- **No anonymous user.** Only loom-server's nkey and the credentials loom-server
  mints are accepted.
- **Per-VM scope.** Every other connection goes to loom-server's auth callout. A
  workspace VM gets its own user/password, valid for its own subjects only
  (`weft.mounts.<vmID>`, `weft.containers.<vmID>`, `weft.exec.<vmID>.>`, ...); it
  cannot subscribe to another VM's subject.
- **No secret in the image or the broker.** The broker is given two *public* keys.
  The seeds stay in loom-server and reach it by reference (a mounted file or a
  systemd credential), never in an environment variable or a committed config.
- **JetStream store** in `/data`, mode 0700, owned by uid 65532 (a named volume
  inherits both).

Without the keys file the broker refuses to start.

## Set up

Generate two seeds once (`go install github.com/nats-io/nkeys/nk@latest`) and keep
them mode 0600:

```sh
umask 077
nk -gen user    > loom.seed      # loom-server's own identity
nk -gen account > callout.seed   # signs the per-VM credentials
```

Give the broker the public halves, as `keys.conf`:

```text
LOOM_USER_KEY      = "U..."     # nk -inkey loom.seed -pubout
CALLOUT_ISSUER_KEY = "A..."     # nk -inkey callout.seed -pubout
```

### Docker Compose

```yaml
services:
  nats:
    image: ghcr.io/openweft/weft-nats:v2.12.15
    restart: unless-stopped
    volumes:
      - nats-data:/data
    secrets:
      - source: weft_nats_keys
        target: /etc/weft-nats/keys.conf

  loom:
    image: ghcr.io/openweft/weft-loom-server:latest
    environment:
      WEFT_NATS_URL: nats://nats:4222
      WEFT_LOOM_NATS_NKEY_SEED_FROM: file:/run/secrets/loom_nkey_seed
      WEFT_LOOM_NATS_CALLOUT_SEED_FROM: file:/run/secrets/loom_callout_seed
    secrets: [loom_nkey_seed, loom_callout_seed]
    depends_on: [nats]

secrets:
  weft_nats_keys:    { file: ./keys.conf }
  loom_nkey_seed:    { file: ./loom.seed }
  loom_callout_seed: { file: ./callout.seed }

volumes:
  nats-data:
```

The broker port is not published: guests must reach `nats:4222` on the
compose network (or publish it deliberately for VMs on other hosts).

### systemd (podman or docker)

```ini
# /etc/systemd/system/weft-nats.service
[Service]
LoadCredential=keys.conf:/etc/weft-nats/keys.conf
ExecStart=/usr/bin/podman run --rm --name weft-nats -p 4222:4222 \
  -v weft-nats-data:/data \
  -v ${CREDENTIALS_DIRECTORY}/keys.conf:/etc/weft-nats/keys.conf:ro \
  ghcr.io/openweft/weft-nats:v2.12.15
ExecStop=/usr/bin/podman stop weft-nats
Restart=on-failure
```

loom-server reads its seeds with `LoadCredentialEncrypted=` and
`WEFT_LOOM_NATS_NKEY_SEED_FROM=systemd-creds:loom-nkey-seed` (and the callout
seed likewise); see the weft-loom-server admin guide.

## Behaviour to know

- A VM credential is revoked for new connections when the VM exits; a connection
  already open stays until it closes.
- Needs weft-loom-server with callout support (v0.6.0 or later); an older
  loom-server cannot mint guest credentials, so its VMs are refused.
- The config is `/etc/weft-nats/nats-server.conf` in this repository.
  Mounting a different `-c` file replaces it, and with it the guarantees above.

## Releases

Tags are the nats-server version (`vX.Y.Z`); `Dockerfile`'s `NATS_VERSION` is the
single place to bump.

## License

See [LICENSE](LICENSE).

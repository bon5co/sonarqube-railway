# sonarqube-railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/deploy/sonarqube-or-just-updated-your-scan-hist?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

**Deploy on Railway:** [SonarQube template](https://railway.com/deploy/sonarqube-or-just-updated-your-scan-hist?referralCode=Z1xivh&utm_medium=integration&utm_source=template&utm_campaign=generic)

A thin wrapper around the official `sonarqube` Community image that makes it deployable on
Railway. Everything here exists because it was measured, not assumed.

## What the wrapper changes

**The embedded Elasticsearch bootstrap check.** SonarQube starts its embedded search node with
`-Des.enforce.bootstrap.checks=true`, so it runs the production bootstrap checks and refuses to
start when the host's `vm.max_map_count` is below `262144`:

```
bootstrap check failure [1] of [1]: max virtual memory areas vm.max_map_count [65530] is too
low, increase to at least [262144]
```

A container on Railway cannot `sysctl`. The wrapper removes the requirement instead of raising
the limit, with `SONAR_SEARCH_JAVAADDITIONALOPTS=-Dnode.store.allow_mmap=false`, which makes
Lucene use `niofs` so the mmap check no longer applies. Verified by deliberately setting
`vm.max_map_count=65530` on the build host: without the flag the node dies during startup, with
it SonarQube reaches `status: UP` in under a minute and logs zero bootstrap check failures.

**Persistence on one volume.** Railway gives a service exactly one volume, and the image declares
four. The volume is mounted at `/opt/sonarqube/extensions`, which holds the plugins an operator
installs through the Marketplace — the part that cannot be rebuilt — and the Elasticsearch index
is relocated onto the same volume with `sonar.path.data`. Because mounting over `extensions`
hides the plugins the image ships, the Dockerfile stashes a copy at `/opt/sonarqube/extensions-image`
and the entrypoint seeds an empty volume from it exactly once. Docker copies image content into an
empty named volume by itself; Railway does not, so this cannot be left to the runtime.

**Volume ownership.** Railway mounts volumes root-owned while the image runs as uid 1000. The
entrypoint takes ownership as root and then drops privileges with `setpriv` (this image has no
`gosu` or `su-exec`).

**The port.** Railway injects `$PORT`; SonarQube only reads `sonar.web.port`. The entrypoint
forwards it.

**The default administrator login.** The stock image ships a documented default administrator
login and does not force a change on first use — it validates over the API, mints admin tokens and
creates projects. On a public URL that hands the first stranger the instance. So:

- the container **refuses to start** unless `SONAR_ADMIN_PASSWORD` is set, and
- once the web server answers, the administrator login is changed to that value, after which the
  default is rejected.

The seeding step is idempotent: if the login already matches `SONAR_ADMIN_PASSWORD` it does
nothing, and if it matches neither the default nor `SONAR_ADMIN_PASSWORD` it assumes an operator
changed it by hand and leaves it alone. A container killed part-way through a long first boot
simply retries on the next start.

## Environment

| Variable | Required | Notes |
| --- | --- | --- |
| `SONAR_ADMIN_PASSWORD` | yes | Refuses to boot without it. SonarQube enforces a strength rule, so include mixed case, a digit and a symbol. |
| `SONAR_JDBC_URL` | yes | `jdbc:postgresql://<host>:5432/postgres` |
| `SONAR_JDBC_PASSWORD` | yes | |
| `SONAR_JDBC_USERNAME` | no | Defaults to `postgres`. |
| `PORT` | no | Injected by Railway; defaults to `9000`. |

## Requirements

PostgreSQL is required — SonarQube will not run a production instance on its embedded database.

**Memory: 2 GB minimum.** Measured on the wrapper image: OOM-killed at 1 GB after 21 s, healthy
at 2 GB, steady at roughly 1.8 GiB resident. Railway's Free (0.5 GB) and Trial (1 GB) per-service
limits cannot run it.

## Build

Pushes to `main` publish `ghcr.io/bon5co/sonarqube-railway:26.8.0` and `:latest`. The base image
is pinned by digest.

# Changelog

All notable changes to this project are documented here.

## [Unreleased] - 2026-06-28

### Fixed

- **Container crash loop (critical).** `start.sh`'s monitor loop checked
  `pgrep supervisord`, but supervisord runs as `python3` (its `comm`), so the
  check never matched and the container called `exit 1` every ~60s — observed as
  70+ Docker restarts on the host. The container now runs supervisord in the
  foreground (`exec supervisord -n`, `nodaemon=true`) as its main process; the
  bash monitor/cleanup loop and the `pgrep` self-kill were removed. Docker's
  restart policy is now the single authority on container lifecycle.
- **HAProxy 3.4 segfault.** The current Alpine base ships HAProxy 3.4, whose
  `external-check` implementation segfaults on Alpine/musl while parsing the
  config (`exit 139`), so HAProxy never started. Replaced the `external-check`
  curl probe with HAProxy's built-in TCP health-check on each Tor HTTPTunnel
  port. A dead instance is pulled from rotation and Supervisor restarts it.
  `check_tor.sh` is no longer needed and was removed.

### Changed

- **Multi-arch image (amd64 + arm64).** CI now uses `docker/setup-qemu-action`,
  `docker/setup-buildx-action` and `docker/build-push-action@v6` to build and
  push a multi-arch manifest to Docker Hub and GHCR. Previously only
  `linux/amd64` was built, forcing QEMU emulation on arm64 hosts (Apple Silicon).
  PR builds no longer push (build-only).
- **Logs go to `docker logs`.** Tor logs via `--Log "notice stdout"` (previously
  `warn syslog`, which was silently dropped — no syslogd runs in the container).
  Supervisor programs write to `/dev/fd/1` with rotation disabled
  (`stdout_logfile_maxbytes=0`, `redirect_stderr=true`) and supervisord's own
  logfile is `/dev/null`. No more unbounded log files inside the container;
  rotation is handled by Docker (`--log-opt max-size`/`max-file`).

### Added

- **`tini` as PID 1** (`ENTRYPOINT ["/sbin/tini","--"]`) to reap short-lived
  children and forward signals cleanly.
- **`MaxMemInQueues "64 MB"`** per Tor instance — caps worst-case queue memory.
- **Configurable circuit rotation** via env vars `NEW_CIRCUIT_PERIOD` and
  `MAX_CIRCUIT_DIRTINESS` (both default `30`, previously hardcoded `15`).

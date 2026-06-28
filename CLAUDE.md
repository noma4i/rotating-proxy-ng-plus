# rotating-proxy-ng-plus

Лёгкий ротируемый Tor HTTP-прокси: N независимых Tor-инстансов за HAProxy (TCP
round-robin), один общий прокси-порт на выходе. Образ публикуется как
`noma4i/rotating-proxy-ng-plus` (Docker Hub + GHCR).

## Архитектура

| Компонент   | Роль                                                                                                  |
| ----------- | ---------------------------------------------------------------------------------------------------- |
| `tini`      | PID 1: reaping детей, проброс сигналов (`ENTRYPOINT`)                                                |
| `start.sh`  | Генерирует `supervisord.conf` + `haproxy.cfg` под `$tors`, затем `exec supervisord -n` (foreground) |
| supervisord | Запускает/перезапускает haproxy и N tor; главный процесс контейнера (`nodaemon=true`)                |
| N × tor     | `SocksPort 0`, `HTTPTunnelPort 20000+i`, отдельный `DataDirectory /var/lib/tor/10000+i`             |
| haproxy     | `frontend rotating_proxies` (5566, mode tcp) → `backend tor` (roundrobin, tcp-check); stats на 4444 |

Жизненным циклом контейнера управляет ТОЛЬКО Docker restart policy: если
supervisord падает — контейнер выходит и Docker его перезапускает. Самодельных
bash-watchdog'ов нет (раньше был — вызывал crash loop, см. CHANGELOG).

## Порты

| Порт        | Назначение                                          |
| ----------- | --------------------------------------------------- |
| 5566        | Прокси (HAProxy frontend, mode tcp) — точка входа    |
| 4444        | HAProxy stats: `/haproxy?stats`                     |
| 20000+i     | HTTP-tunnel каждого tor-инстанса (internal backend) |

## Переменные окружения

| Переменная              | Default | Назначение                                          |
| ----------------------- | ------- | --------------------------------------------------- |
| `tors`                  | 10      | Число Tor-инстансов                                 |
| `NEW_CIRCUIT_PERIOD`    | 30      | `--NewCircuitPeriod` (сек): как часто строится цепь |
| `MAX_CIRCUIT_DIRTINESS` | 30      | `--MaxCircuitDirtiness` (сек): время жизни цепи     |

Прочие флаги tor фиксированы в `start.sh`: `UseEntryGuards 0`,
`CircuitBuildTimeout 5`, `MaxMemInQueues "64 MB"`, `Log "notice stdout"`.

## Health-check

HAProxy делает встроенный TCP-check к каждому `HTTPTunnelPort` (`check inter 10s
fastinter 5s downinter 5s rise 2 fall 2`). Мёртвый инстанс выводится из ротации,
supervisor его перезапускает. Внешний curl-check (`external-check`) НЕ используется:
в HAProxy 3.4 на Alpine/musl он segfault'ит при парсинге конфига.

## Логи

Всё идёт в `docker logs` (stdout): tor — `--Log "notice stdout"`; supervisor-программы
пишут в `/dev/fd/1` с отключённой ротацией-в-файл (`stdout_logfile_maxbytes=0`,
`redirect_stderr=true`); `supervisord logfile=/dev/null`. Файлов внутри контейнера не
растёт — ротация на стороне Docker (`--log-opt max-size`/`max-file`).

## Структура

```
Dockerfile                       # alpine + tor/curl/haproxy/bash/supervisor/tini
docker-compose.yml               # локальный build, tors=5
start.sh                         # генерация конфигов + exec supervisord -n
torrc                            # опциональный шаблон (ExitNodes), монтируется при желании
.github/workflows/docker-image.yml  # multi-arch CI
README.md / CHANGELOG.md / CLAUDE.md
```

## Сборка и публикация

CI (`docker-image.yml`) на push в `master` собирает multi-arch манифест
(`linux/amd64,linux/arm64`) через buildx и пушит в Docker Hub + GHCR. PR — только
сборка, без push. Локально: `docker build -t rpng-test .` (нативная арка хоста).

## Использование

```bash
docker run -d -p 5566:5566 -p 4444:4444 --env tors=10 noma4i/rotating-proxy-ng-plus
curl --proxy 127.0.0.1:5566 https://icanhazip.com   # повтор даёт другой exit-IP
```

## Gotchas

- HAProxy 3.4 `external-check` segfault'ит на Alpine — только встроенный tcp-check.
- supervisord имеет `comm=python3` — НЕ матчится `pgrep supervisord` (исторический баг).
- На arm64-хостах обязателен arm64-вариант образа, иначе QEMU-эмуляция (раздувает CPU/RAM).
- `torrc` в репо (`ExitNodes`) применяется только если смонтирован в `/etc/tor/torrc`.

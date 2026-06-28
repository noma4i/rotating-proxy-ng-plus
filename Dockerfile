FROM alpine:latest

RUN apk update && apk --no-cache add tor curl haproxy bash supervisor tini \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/*

ADD --chmod=755 start.sh /usr/local/bin/

RUN mkdir -p /usr/local/etc/ /var/log /var/lib/tor /var/run/tor

EXPOSE 5566 4444

# tini as PID 1 reaps short-lived children (health-check probes) and forwards signals.
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["/usr/local/bin/start.sh"]

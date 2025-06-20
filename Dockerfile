FROM alpine:latest

RUN apk update && apk --no-cache add tor curl haproxy bash supervisor \
    && rm -rf /var/cache/apk/* \
    && rm -rf /tmp/*

ADD --chmod=755 start.sh check_tor.sh /usr/local/bin/

RUN mkdir -p /usr/local/etc/ /var/log /var/lib/tor /var/run/tor

EXPOSE 5566 4444

CMD ["/usr/local/bin/start.sh"]

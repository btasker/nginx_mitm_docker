FROM nginx:1.21.1-alpine

ENV SERVER_NAME=_
ENV DEST=https://\$http_host
ENV DNS_RESOLVER=8.8.8.8

# Some versions of Nginx will crash out if there isn't at least one file matching an include glob
# it doesn't need to contain anything
COPY nginx.cnf.template /nginx.cnf
RUN mkdir -p /etc/nginx/conf.d/ && echo > /etc/nginx/conf.d/00_default.conf && mkdir /root/pcaps && apk add tcpdump

EXPOSE 80
EXPOSE 443

CMD ["/bin/sh", "-c", "envsubst '$DEST $SERVER_NAME $DNS_RESOLVER' < /nginx.cnf > /etc/nginx/nginx.conf && exec nginx -g 'daemon off;'"]


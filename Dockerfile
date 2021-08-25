FROM nginx:1.21.1-alpine

ENV SERVER_NAME=repro.bentasker.co.uk
ENV DEST=https://snippets.bentasker.co.uk

# Some versions of Nginx will crash out if there isn't at least one file matching an include glob
# it doesn't need to contain anything
COPY nginx.cnf.template /nginx.cnf
RUN mkdir -p /etc/nginx/conf.d/ && touch /etc/nginx/conf.d/00_empty.conf

EXPOSE 80
EXPOSE 443

CMD ["/bin/sh", "-c", "envsubst '$DEST $SERVER_NAME' < /nginx.cnf > /etc/nginx/nginx.conf && exec nginx -g 'daemon off;'"]


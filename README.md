# Nginx HTTP Request Interception Container

## Overview

This docker image stands up a copy of Nginx, using a predefined configuration that you can modify using environment variables at run time.

The default configuration is to have a plaintext-listener which proxies onwards (normally to a HTTPS destination), so that you can view/capture requests whilst still having them placed against a HTTPS origin (that you presumably do not control).

This implies some control over the client, as you'll need to be able to do at least one of the following

* Reconfigure the client to use HTTP rather than HTTPS *and*
* Reconfigure the client to connect to a destination of your choosing *or*
* Reconfigure local DNS and/or routing so that the client connects to your destination thinking it's going to the original

If you have the ability to install a root certificate on the client or find that it doesn't validate cert chains, then you can also perform a HTTPS-to-plain attack (see Advanced usage for an example)


----

## Running

### Docker Hub

The image is on [Docker Hub](https://hub.docker.com/repository/docker/bentasker12/nginx_simple_mitm) so you can run

    docker run -p 8080:80 -e SERVER_NAME=repro.bentasker.co.uk -e DEST=https://www.google.com bentasker12/nginx_simple_mitm:initial


### Locally

Or, to run from a copy of this repo

    docker built -t nginx_mitm .
    docker run -p 8080:80 -e SERVER_NAME=repro.bentasker.co.uk -e DEST=https://www.google.com nginx_mitm


### Environment Vars

The Nginx configuration is influenced by a set of environment variables:

* `SERVER_NAME`: The HTTP host header the config should answer to (default is `_` - which answers everything)
* `DEST`: Where requests should be sent on to, this must include scheme (e.g. `https://example.com` not just `example.com`). [Nginx variables](http://nginx.org/en/docs/varindex.html) can be used here for more advanced usage.
* `DNS_RESOLVER`: A DNS server that Nginx should use when resolving upstream names. Defaults to `8.8.8.8`


### Logging

Logs are written to `stdout` and have the following format:

    log_format  main  '$remote_addr\t-\t$remote_user\t[$time_local]\t$server_name\t"$request"\t'
                    '$status\t$body_bytes_sent\t"$http_referer"\t'
                    '"$http_user_agent"\t"$http_x_forwarded_for"\t$request_time\t"$http_host"\tForwarded to:\t$upstream_addr\t'
                    '\t$upstream_bytes_received\t"$upstream_http_server"\t$upstream_connect_time\t$upstream_status\t$upstream_response_time\t';



### Ports

The `Dockerfile` lists TCP 80 and TCP 443 as being exposed.

However, at runtime you can publish these to whatever port you need to (you'll need to be a privileged user to publish to port numbers < 1024).

In the examples given, port 80 is published to 8080 on the host: `-p 8080:80`


----

## Usage

### Using a custom server name and forwarding to Google:

    docker run -p 8080:80 -e SERVER_NAME=repro.bentasker.co.uk -e DEST=https://www.google.com bentasker12/nginx_simple_mitm:initial
    curl http://127.0.0.1:8080 -H "Host: repro.bentasker.co.uk"

Giving log-line:

    172.17.0.1	-	-	[25/Aug/2021:09:58:30 +0000]	repro.bentasker.co.uk	"GET / HTTP/1.1"	200	15174	"-"	"curl/7.74.0"	"-"	0.100	"repro.bentasker.co.uk"	Forwarded to:	142.250.180.4:443		15772	"gws"	0.040	200	0.100


### Accepting anything and forwarding to Google

    docker run -p 8080:80 -e DEST=https://www.google.com bentasker12/nginx_simple_mitm:initial


### Using as a wildcard proxy

The default config is considered, well, default - so it's possible to have it accept *any* HTTP connection and then forward it onto the same upstream.

To do this, we pass an Nginx variable in the `DEST` env var:

    docker run -p 8080:80 -e DEST='https://$http_host' bentasker12/nginx_simple_mitm:initial

Any HTTP request will then be proxied onto it's destination:

    curl http://127.0.0.1:8080 -H "Host: snippets.bentasker.co.uk"

Giving logline

    172.17.0.1	-	-	[25/Aug/2021:10:07:13 +0000]	_	"GET / HTTP/1.1"	200	8116	"-"	"curl/7.74.0"	"-"	0.193	"snippets.bentasker.co.uk"	Forwarded to:	195.181.164.178:443		9177	"BunnyCDN-UK1-656"	0.072	200	0.140

If `8.8.8.8` isn't reachable by the docker container, you'll need to specify an alternate DNS resolver with `-e DNS_RESOLVER=[ip:[port]]`. Acceptable format is detailed in the [Nginx docs](http://nginx.org/en/docs/http/ngx_http_core_module.html#resolver)


-----

## Advanced

### Providing additional configuration files

The default config stands up a single server block on port 80.

You _might_ want to be able to do more than this though. The Nginx configuration is set up to pull in any files ending in `.conf` within `/etc/nginx/conf.d` so you can tell Docker to export this directory from your local filesystem

    docker run -v /full/path/to/dir:/etc/nginx/conf.d -p 8080:80 bentasker12/nginx_simple_mitm:initial

Note: there *must* be at least 1 `.conf` file present, even if it's empty, otherwise some versions of Nginx will fail to start.

This allows you to achieve a variety of ends, including setting up a simple HTTPS mitm:

    server {
            listen 443;

            server_name snippets.bentasker.co.uk;

            ssl on;
            ssl_certificate /etc/nginx/conf.d/mycert.crt;
            ssl_certificate_key /etc/nginx/conf.d/mycert.key;

            root /usr/share/nginx/empty;
            index index.php index.html index.htm;

            location / {
                proxy_set_header Host plaintext_proxy;
                proxy_pass http://127.0.0.1:9080;
            }
    }

    server {
            listen   127.0.0.1:9080;

            root /usr/share/nginx/empty;
            index index.php index.html index.htm;

            server_name plaintext_proxy;

            location / {
                proxy_pass https://snippets.bentasker.co.uk;
            }
    }

Where your exported directory also contains `mycert.crt` and `mycert.key` (assuming you can have the client app trust the certs).

Traffic could then be captured as follows

    docker run --name=nginx_mitm -v /home/ben/tmp/nginxconfs:/etc/nginx/conf.d -v /home/ben/tmp/pcaps:/root/pcaps bentasker12/nginx_simple_mitm:initial
    docker exec -it nginx_mitm tcpdump -i lo -s0 -w /root/pcaps/cap.pcap -v port 9080

(In our example config, the plaintext version of the traffic is sent to port 9080 on loopback, so that's what we filter for)


### Packet Capturing inside the container

It's alluded to in the example above, but `tcpdump` is installed in the container.

For convenience, a directory `/root/pcaps` is also created, so that you can map a local directory to it:

    docker run --name=nginx_mitm -v /home/ben/tmp/nginxconfs:/etc/nginx/conf.d -v /home/ben/tmp/pcaps:/root/pcaps bentasker12/nginx_simple_mitm:initial

You can then exec `tcpdump`:

    docker exec -it nginx_mitm tcpdump -i lo -s0 -w /root/pcaps/cap.pcap -v port 9080

And the packetcaptures will get written out into your local directory

# Reproducing Linkerd issue 6035

https://github.com/linkerd/linkerd2/issues/6035

Workload cannot make HTTPS (encrypted) requests via a http proxy while the pod has the
linkerd proxy injected. HTTP (unencrypted) requests work fine.

This works
```
App -> HTTP Proxy -> Internet
```

This fails
```
App -> Linkerd Proxy -> HTTP Proxy -> Internet (HTTPS)
```

## Setup

For the setup, we build tinyproxy from source to resolve an issue where the correct HTTP version
wasn't being returned. https://github.com/tinyproxy/tinyproxy/commit/a869e71ac382acb2a8b4442477ed675e5bf0ce76
However, this only resolves the issue for HTTP requests, not HTTPS

1. git submodule init
2. git submodule update
3. kind create cluster --config cluster.yaml
4. docker build -t tinyproxy-src -f tinyproxy/tinyproxy.Dockerfile tinyproxy/
5. kind load docker-image --name linkerd-6035 tinyproxy-src
6. kubectl apply -f linkerd.yaml
7. kubectl apply -f tinyproxy.yaml
8. kubectl apply -f workload.yaml

note: tinyproxy (http://tinyproxy.github.io/) is deliberately not injected with the linkerd proxy.
This is to simulate it being outside the mesh (as is the situation in my case. The tinyproxy is a
VM outside the Kubernetes cluster)

`workload.yaml` deploys 2 pods. One with the Linkerd proxy injected, another without.
Both run the same curl command requesting `https://google.com` via the tinyproxy service.
The expected output is a 301 response, redirecting to `www.google.com`.

## The fix

in `tinyproxy/tinyproxy/src/reqs.c`, update `SSL_CONNECTION_RESPONSE` and change `HTTP/1.0` to `HTTP/1.1`.
Rebuild the image, load it into the kind cluster and restart the tinyproxy deployment

### Linkerd Proxy injected

Request fails with the following output:

```
* Connected to tinyproxy (10.96.106.10) port 8888 (#0)
* allocate connect buffer!
* Establish HTTP proxy tunnel to google.com:443
> CONNECT google.com:443 HTTP/1.1
> Host: google.com:443
> User-Agent: curl/7.80.0
> Proxy-Connection: Keep-Alive
> 
< HTTP/1.0 200 OK
< proxy-agent: tinyproxy/1.11.0
< date: Mon, 04 Jul 2022 08:41:06 GMT
< 
* Proxy replied 200 to CONNECT request
* CONNECT phase completed!
* ALPN, offering h2
* ALPN, offering http/1.1
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: none
} [5 bytes data]
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
} [512 bytes data]
* OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to google.com:443 
* Closing connection 0
curl: (35) OpenSSL SSL_connect: SSL_ERROR_SYSCALL in connection to google.com:443 
Stream closed EOF for default/curl (curl)
```

### Linkerd Proxy NOT injected

Request succeeds with the followign output

```
* Connected to tinyproxy (10.96.106.10) port 8888 (#0)
* allocate connect buffer!
* Establish HTTP proxy tunnel to google.com:443
> CONNECT google.com:443 HTTP/1.1
> Host: google.com:443
> User-Agent: curl/7.80.0
> Proxy-Connection: Keep-Alive
> 
< HTTP/1.0 200 Connection established
< Proxy-agent: tinyproxy/1.11.0
< 
* Proxy replied 200 to CONNECT request
* CONNECT phase completed!
* ALPN, offering h2
* ALPN, offering http/1.1
*  CAfile: /etc/ssl/certs/ca-certificates.crt
*  CApath: none
} [5 bytes data]
* TLSv1.3 (OUT), TLS handshake, Client hello (1):
} [512 bytes data]
* TLSv1.3 (IN), TLS handshake, Server hello (2):
{ [122 bytes data]
* TLSv1.3 (IN), TLS handshake, Encrypted Extensions (8):
{ [15 bytes data]
* TLSv1.3 (IN), TLS handshake, Certificate (11):
{ [6386 bytes data]
* TLSv1.3 (IN), TLS handshake, CERT verify (15):
{ [79 bytes data]
* TLSv1.3 (IN), TLS handshake, Finished (20):
{ [52 bytes data]
* TLSv1.3 (OUT), TLS change cipher, Change cipher spec (1):
} [1 bytes data]
* TLSv1.3 (OUT), TLS handshake, Finished (20):
} [52 bytes data]
* SSL connection using TLSv1.3 / TLS_AES_256_GCM_SHA384
* ALPN, server accepted to use h2
* Server certificate:
*  subject: CN=*.google.com
*  start date: Jun  6 08:29:46 2022 GMT
*  expire date: Aug 29 08:29:45 2022 GMT
*  subjectAltName: host "google.com" matched cert's "google.com"
*  issuer: C=US; O=Google Trust Services LLC; CN=GTS CA 1C3
*  SSL certificate verify ok.
* Using HTTP2, server supports multiplexing
* Connection state changed (HTTP/2 confirmed)
* Copying HTTP/2 data in stream buffer to connection buffer after upgrade: len=0
} [5 bytes data]
* Using Stream ID: 1 (easy handle 0x4001cf7a90)
} [5 bytes data]
> GET / HTTP/2
> Host: google.com
> user-agent: curl/7.80.0
> accept: */*
> 
{ [5 bytes data]
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
{ [279 bytes data]
* TLSv1.3 (IN), TLS handshake, Newsession Ticket (4):
{ [279 bytes data]
* old SSL session ID is stale, removing
{ [5 bytes data]
< HTTP/2 301 
< location: https://www.google.com/
< content-type: text/html; charset=UTF-8
< date: Mon, 04 Jul 2022 08:43:51 GMT
< expires: Wed, 03 Aug 2022 08:43:51 GMT
< cache-control: public, max-age=2592000
< server: gws
< content-length: 220
< x-xss-protection: 0
< x-frame-options: SAMEORIGIN
< alt-svc: h3=":443"; ma=2592000,h3-29=":443"; ma=2592000,h3-Q050=":443"; ma=2592000,h3-Q046=":443"; ma=2592000,h3-Q043=":443"; ma=2592000,quic=":443"; ma=2592000; v="46,43"
< 
{ [5 bytes data]
<HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">
<TITLE>301 Moved</TITLE></HEAD><BODY>
<H1>301 Moved</H1>
The document has moved
<A HREF="https://www.google.com/">here</A>.
</BODY></HTML>

100   220  100   220    0     0   1141      0 --:--:-- --:--:-- --:--:--  1222
* Connection #0 to host tinyproxy left intact
Stream closed EOF for default/curl (curl)
```# linkerd2-repro-6035

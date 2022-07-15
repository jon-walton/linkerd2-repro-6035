FROM alpine:3.10 as build

COPY /tinyproxy/ /src
WORKDIR /src

RUN apk update \
  && \
  apk add --no-cache \
  make \
  automake \
  gcc \
  musl-dev \
  asciidoc \
  autoconf \
  && \
  ./autogen.sh \
  && \
  ./configure \
  --prefix=/tmp \
  --enable-xtinyproxy \
  --enable-filter \
  --enable-upstream \
  --enable-transparent \
  --enable-reverse \
  && \
  make \
  && \
  make install \
  && \
  rm -rf /tmp/share/doc /tmp/share/man

FROM alpine:3.10

COPY --from=build /tmp/share /tinyproxy/share
COPY --from=build /tmp/etc /tinyproxy/etc
COPY --from=build /tmp/bin /tinyproxy/bin

RUN apk update \
  && \
  apk add --no-cache \
  tini \
  ca-certificates \
  && sed -i -e '/^Allow /s/^/#/' \
  -e '/^ConnectPort /s/^/#/' \
  -e '/^#DisableViaHeader /s/^#//' \
  /tinyproxy/etc/tinyproxy/tinyproxy.conf

ENTRYPOINT ["tini", "--", "/tinyproxy/bin/tinyproxy"]
CMD ["-d", "-c", "/tinyproxy/etc/tinyproxy/tinyproxy.conf"]

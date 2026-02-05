FROM ubuntu:22.04

RUN apt-get update && apt-get install -y build-essential libpcre3-dev zlib1g-dev libssl-dev curl ccache && /usr/sbin/update-ccache-symlinks && ln -sf /usr/bin/ccache /usr/lib/ccache/cc

ENV CCACHE_DIR=/ccache
ENV PATH="/usr/lib/ccache:$PATH"

WORKDIR /src


COPY src_project/nginx .








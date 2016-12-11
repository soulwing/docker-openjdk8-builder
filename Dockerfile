FROM debian:jessie

RUN apt-get update && \
    apt-get install -y git mercurial zip bzip2 tar curl make gcc g++ cpio \
          ca-certificates ca-certificates-java libX11-dev libxext-dev \
          libxrender-dev libxtst-dev libxt-dev libasound2-dev libcups2-dev \
          libfreetype6-dev build-essential autoconf ccache openjdk-7-jdk && \
    mkdir /openjdk

COPY bin/ /usr/local/bin/
COPY patches/ /openjdk/patches/
RUN chmod 0755 /usr/local/bin/*

ENV JAVA_HOME=/usr/lib/jvm/java-7-openjdk-amd64
WORKDIR /openjdk
CMD [ "/usr/local/bin/build.sh" ]

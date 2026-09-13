FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
        openssh-server \
        sudo \
        python3 \
        python3-pip \
        openjdk-11-jdk-headless \
        curl \
        wget \
        rsync \
        iproute2 \
        iputils-ping \
        procps && \
    rm -rf /var/lib/apt/lists/*

# Пользователь, под которым будем работать как на реальных VM
RUN useradd \
        --create-home \
        --shell /bin/bash \
        student && \
    echo "student ALL=(ALL) NOPASSWD:ALL" \
        > /etc/sudoers.d/student && \
    chmod 0440 /etc/sudoers.d/student

# sshd требует эту директорию
RUN mkdir -p /run/sshd

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
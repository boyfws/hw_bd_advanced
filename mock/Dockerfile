FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
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
        procps \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Пользователь как на реальных VM
RUN useradd \
        --create-home \
        --shell /bin/bash \
        team && \
    echo "team ALL=(ALL) NOPASSWD:ALL" \
        > /etc/sudoers.d/team && \
    chmod 0440 /etc/sudoers.d/team

# Настройка SSH
RUN mkdir -p /run/sshd && \
    printf '%s\n' \
        'PasswordAuthentication no' \
        'PermitRootLogin no' \
        > /etc/ssh/sshd_config.d/99-mock.conf

COPY entrypoint.sh /entrypoint.sh

RUN chmod +x /entrypoint.sh

EXPOSE 22

ENTRYPOINT ["/entrypoint.sh"]
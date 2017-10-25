ARG VERSION=docker:stable-dind
FROM ${VERSION}

RUN apk add --no-cache git tmux vim curl bash-completion bash jq openssh libc6-compat


RUN curl https://releases.hashicorp.com/nomad/0.6.3/nomad_0.6.3_linux_amd64.zip?_ga=2.228911324.1502434427.1508857331-314702724.1508857331 -o nomad.zip \
    && unzip -d /usr/local/bin nomad \
    && rm nomad.zip

# Add bash completion and set bash as default shell
RUN mkdir /etc/bash_completion.d \
    && curl https://raw.githubusercontent.com/docker/cli/master/contrib/completion/bash/docker -o /etc/bash_completion.d/docker \
    && sed -i "s/ash/bash/" /etc/passwd
 
# Replace modprobe with a no-op to get rid of spurious warnings
# (note: we can't just symlink to /bin/true because it might be busybox)
RUN rm /sbin/modprobe && echo '#!/bin/true' >/sbin/modprobe && chmod +x /sbin/modprobe

# Install a nice vimrc file and prompt (by soulshake)
COPY ["docker-prompt","/usr/local/bin/"]
COPY [".vimrc",".profile", ".inputrc", ".gitconfig", "./root/"]
COPY ["motd", "/etc/motd"]
COPY ["daemon.json", "/etc/docker/"]

ARG docker_storage_driver=overlay2


# Move to our home
WORKDIR /root

# Setup certs and ssh keys
RUN mkdir -p /var/run/pwd/certs && mkdir -p /var/run/pwd/uploads \
    && ssh-keygen -N "" -t rsa -f  /etc/ssh/ssh_host_rsa_key >/dev/null \
    && mkdir ~/.ssh && ssh-keygen -N "" -t rsa -f ~/.ssh/id_rsa \
    && cat ~/.ssh/id_rsa.pub > ~/.ssh/authorized_keys


ENV DOCKER_STORAGE_DRIVER=$docker_storage_driver
# Override AWS variable to prevent nomad fingerprinting
ENV AWS_ENV_URL="http://localhost:2"

# Remove IPv6 alias for localhost and start docker in the background ...
CMD cat /etc/hosts >/etc/hosts.bak && \
    sed 's/^::1.*//' /etc/hosts.bak > /etc/hosts && \
    sed -i "s/\DOCKER_STORAGE_DRIVER/$DOCKER_STORAGE_DRIVER/" /etc/docker/daemon.json && \
    sed -i "s/\PWD_IP_ADDRESS/$PWD_IP_ADDRESS/" /etc/docker/daemon.json && \
    sed -i "s/\DOCKER_TLSENABLE/$DOCKER_TLSENABLE/" /etc/docker/daemon.json && \
    sed -i "s/\DOCKER_TLSCACERT/$DOCKER_TLSCACERT/" /etc/docker/daemon.json && \
    sed -i "s/\DOCKER_TLSCERT/$DOCKER_TLSCERT/" /etc/docker/daemon.json && \
    sed -i "s/\DOCKER_TLSKEY/$DOCKER_TLSKEY/" /etc/docker/daemon.json && \
    umount /var/lib/docker && mount -t securityfs none /sys/kernel/security && \
    echo "root:root" | chpasswd &> /dev/null && \
    /usr/sbin/sshd -o PermitRootLogin=yes -o PrintMotd=no 2>/dev/null && \
    dockerd &>/docker.log & nomad agent -dev -network-interface eth0 &>nomad.log & \
    while true ; do /bin/bash -l; done
# ... and then put a shell in the foreground, restarting it if it exits

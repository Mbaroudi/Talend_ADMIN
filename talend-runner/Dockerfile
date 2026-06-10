# Talend execution node. Rundeck dispatches job runs here over SSH and the
# compiled job artifacts are read from the shared /artifacts volume.
FROM eclipse-temurin:11-jdk-jammy

RUN apt-get update && apt-get install -y --no-install-recommends \
        openssh-server curl ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /var/run/sshd /artifacts

# Non-root execution user Rundeck connects as.
RUN useradd -m -s /bin/bash talend

# SSH sessions do not inherit the image ENV (PATH with JAVA_HOME/bin), so
# expose the JVM on the default PATH for Rundeck-dispatched commands.
RUN ln -s "${JAVA_HOME}/bin/java" /usr/local/bin/java

# Key-only SSH.
RUN printf 'PasswordAuthentication no\nPubkeyAuthentication yes\nPermitRootLogin no\n' \
        > /etc/ssh/sshd_config.d/talend.conf

COPY entrypoint.sh /entrypoint.sh
COPY run-talend-job.sh /usr/local/bin/run-talend-job
RUN chmod +x /entrypoint.sh /usr/local/bin/run-talend-job

EXPOSE 22
ENTRYPOINT ["/entrypoint.sh"]

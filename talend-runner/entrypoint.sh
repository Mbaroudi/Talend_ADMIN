#!/bin/bash
# Generate a shared SSH key pair on first boot, authorise it for the `talend`
# user, then run sshd in the foreground. The private key lives on the shared
# `ssh_keys` volume which Rundeck mounts read-only to connect here.
set -euo pipefail

USER_NAME="talend"
HOME_DIR="/home/${USER_NAME}"

mkdir -p /keys
if [ ! -f /keys/id_rsa ]; then
  echo "[talend-runner] Generating SSH key pair into shared volume ..."
  ssh-keygen -t rsa -b 4096 -N '' -C "rundeck@talend-runner" -f /keys/id_rsa
fi
# Rundeck uses a Java SSH client (JSch) that reads the key content and does not
# enforce 0600; 0644 lets the rundeck container user read it on a local stack.
chmod 644 /keys/id_rsa /keys/id_rsa.pub

# Authorise the public key for the talend user.
mkdir -p "${HOME_DIR}/.ssh"
cp /keys/id_rsa.pub "${HOME_DIR}/.ssh/authorized_keys"
chmod 700 "${HOME_DIR}/.ssh"
chmod 600 "${HOME_DIR}/.ssh/authorized_keys"
chown -R "${USER_NAME}:${USER_NAME}" "${HOME_DIR}/.ssh"

# Make artifacts writable by the runner user.
chown -R "${USER_NAME}:${USER_NAME}" /artifacts 2>/dev/null || true

# Host keys, then run sshd.
ssh-keygen -A
echo "[talend-runner] Ready — sshd listening on :22 for user '${USER_NAME}'."
exec /usr/sbin/sshd -D -e

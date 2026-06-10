#!/bin/sh
# Creates the artifact buckets used by the Talend builder and runner.
set -e

mc alias set local "${MINIO_ENDPOINT:-http://minio:9000}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"

mc mb --ignore-existing "local/${MINIO_BUCKET_JOBS}"
mc mb --ignore-existing "local/${MINIO_BUCKET_LOGS}"

echo "MinIO buckets ready: ${MINIO_BUCKET_JOBS}, ${MINIO_BUCKET_LOGS}"

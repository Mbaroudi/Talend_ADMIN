# Talend CI builder: clones a Talend Maven project, compiles it and publishes
# the runnable artifact to the shared /artifacts volume (and optionally MinIO).
FROM maven:3.9-eclipse-temurin-11

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl unzip ca-certificates python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*

# MinIO client (optional artifact upload).
RUN curl -fsSL https://dl.min.io/client/mc/release/linux-amd64/mc \
        -o /usr/local/bin/mc && chmod +x /usr/local/bin/mc

# Isolated Python env for the build API.
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY build_server.py .
COPY scripts/ ./scripts/
RUN chmod +x ./scripts/*.sh

ENV OUTPUT_DIR=/artifacts \
    WORKSPACE_DIR=/tmp/build

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=10s --retries=3 \
    CMD curl -fsS http://localhost:8080/health || exit 1

CMD ["python", "build_server.py"]

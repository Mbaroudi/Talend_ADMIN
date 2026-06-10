# TOS CI-builder: headless Talend Open Studio used as a command-line code
# generator. Builds a runnable Talend job from RAW Studio project sources
# (.item/.properties) — the open-source equivalent of the commercial
# "Talend CI Builder".
#
# The image stays small on purpose:
#   - the Studio (~830 MB zip) is downloaded ONCE at first start into the
#     `tos_studio` volume, not baked into the image;
#   - no GUI: the Eclipse application org.talend.commandline.CommandLine is
#     launched through the equinox launcher with a plain JVM (no GTK/X11);
#   - component/job libraries are resolved ON DEMAND from Maven Central into
#     the Studio's own m2 (persisted in the volume) — no bulk pre-download.
FROM eclipse-temurin:11-jdk-jammy

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl unzip ca-certificates python3 python3-venv \
    && rm -rf /var/lib/apt/lists/*

# Isolated Python env for the build API.
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:${PATH}"

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY build_server.py entrypoint.sh ./
COPY scripts/ ./scripts/
COPY plugin/ ./plugin/
RUN chmod +x entrypoint.sh ./scripts/*.sh

ENV TOS_HOME=/opt/tos \
    OUTPUT_DIR=/artifacts \
    WORKSPACE_DIR=/build

EXPOSE 8080
# The API is up immediately; /health reports studio_ready=false until the
# one-time Studio download completes (see compose start_period).
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
    CMD curl -fsS http://localhost:8080/health || exit 1

ENTRYPOINT ["./entrypoint.sh"]

# Git webhook handler: turns a push into a Rundeck-driven Talend build+run.
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY webhook_handler.py .

RUN useradd -r -s /usr/sbin/nologin webhook && chown -R webhook /app
USER webhook

EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -fsS http://localhost:8080/health || exit 1

CMD ["python", "webhook_handler.py"]

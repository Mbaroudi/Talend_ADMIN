# Talend_ADMIN unified portal (Flask + gunicorn).
FROM python:3.11-slim

RUN apt-get update && apt-get install -y --no-install-recommends curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
COPY templates/ ./templates/

RUN useradd -r -s /usr/sbin/nologin tac && chown -R tac /app
USER tac

EXPOSE 8089
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -fsS http://localhost:8089/health || exit 1

CMD ["gunicorn", "-b", "0.0.0.0:8089", "-w", "2", "--timeout", "30", "app:app"]

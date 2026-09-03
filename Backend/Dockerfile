# Railway deploy image for the FastAPI backend.
#
# Three things this image exists specifically to guarantee (see
# context/pre-deployment-checklist.md items 1/3/4, context/decisions-log.md
# for the verification narrative):
#   1. `ffmpeg` is installed and on PATH — app/services/audio_analysis.py
#      shells out to it to decode every uploaded Voice Diary recording;
#      without it, acoustic analysis silently does nothing (soft-fails),
#      not a crash, but a real feature quietly not working. NOT bundled by
#      Railway's default Python buildpack — installed explicitly below.
#   2. Migrations run automatically on every container start
#      (`alembic upgrade head`, in start.sh) — nothing else runs this.
#   3. The server binds to Railway's injected $PORT, not a hardcoded port.
FROM python:3.12-slim

# ffmpeg: system binary, not a pip package — see
# app/services/audio_analysis.py's own docstring and requirements.txt's
# comment. --no-install-recommends keeps the image lean; apt caches are
# cleaned in the same layer so they don't bloat the final image.
RUN apt-get update \
    && apt-get install -y --no-install-recommends ffmpeg \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Dependencies in their own layer so `docker build` doesn't reinstall them
# on every app-code change.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

RUN chmod +x start.sh

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

# Railway's health check hits GET /health (see railway.json) — no
# EXPOSE'd port is fixed here since $PORT is only known at container
# start time, not build time.
CMD ["./start.sh"]

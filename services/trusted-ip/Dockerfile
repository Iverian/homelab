FROM python:3.13-slim-bookworm@sha256:a5a7017efc5969e00ae2b91c8eb0631049a569652aa4ffc4501769049ae45c72
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
COPY requirements.txt /opt/trusted-ip/requirements.txt
RUN pip install --no-cache-dir --only-binary=:all: -r /opt/trusted-ip/requirements.txt
USER 65532:65532
WORKDIR /app
CMD ["python", "/app/server.py"]

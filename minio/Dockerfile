# Railway builds this service from /minio.
# Silo is the maintained MinIO-compatible fork; pin a release for reproducible builds.
FROM docker.io/pgsty/silo:RELEASE.2026-09-16T00-00-00Z

RUN mkdir -p /data

ENTRYPOINT mkdir -p /data/${STORAGE_S3_BUCKET:-deposium} && exec silo server /data --address ":9000" --console-address ":9001"

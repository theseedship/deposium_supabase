FROM minio/minio:RELEASE.2025-09-07T16-13-09Z

RUN mkdir -p /data

ENTRYPOINT mkdir -p /data/${STORAGE_S3_BUCKET:-deposium} && exec minio server /data --address ":9000" --console-address ":9001"

# Silo S3-Compatible Object Store

Railway builds this service from the `/minio` root directory. The directory and service name remain `minio` so existing Railway settings and internal service URLs continue to work. The Dockerfile now uses [PGSTY Silo](https://hub.docker.com/r/pgsty/silo), a maintained MinIO-compatible fork.

The image is pinned to `RELEASE.2026-09-16T00-00-00Z`. Silo uses the `silo` executable, while keeping the `MINIO_ROOT_USER` and `MINIO_ROOT_PASSWORD` environment variables, the S3 API on port 9000, the console on port 9001, and the `/minio/health/live` endpoint. The existing `/data` volume and `STORAGE_S3_BUCKET` bucket directory are retained.

Before deploying the new image against an existing Railway volume, keep a recoverable copy of its data and record the current image version. The [Silo migration guide](https://silo.pgsty.com/compatibility/migration/) says that MinIO data is generally reusable, but older MinIO versions need a migration check and a validated recovery path. After deployment, check the health endpoint, console, and access to an existing S3 object.

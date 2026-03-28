# giraf-deploy

Docker Compose orchestration for the full GIRAF stack.

## Services

| Service | Port | Source |
|---------|------|--------|
| `core-db` | 5432 | PostgreSQL 16 |
| `core-api` | 8000 | [giraf-core](https://github.com/aau-giraf/giraf-core) (Django) |
| `giraf-ai` | 8100 | [giraf-ai](https://github.com/aau-giraf/giraf-ai) (FastAPI) |
| `weekplanner-db` | 5433 | PostgreSQL 15 |
| `weekplanner-api` | 5171 | [weekplanner](https://github.com/aau-giraf/weekplanner) (.NET 8) |

## Prerequisites

- Docker and Docker Compose
- The following repos cloned as siblings:

```
GIRAF/
├── giraf-core/
├── giraf-ai/
├── weekplanner/
└── giraf-deploy/       ← you are here
```

## Quick Start

```bash
# 1. Create .env from template
cp .env.example .env    # Edit as needed

# 2. Start everything
docker compose up

# 3. (Optional) Start the Expo frontend
cd ../weekplanner/frontend
npm install
npx expo start
```

All backend services will be available once the health checks pass.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `JWT_SECRET` | Yes | — | Shared JWT signing key (min 32 chars) |
| `GIRAF_DB_PASSWORD` | No | `localdev123` | PostgreSQL password for all databases |
| `IMAGE_PROVIDER` | No | `mock` | giraf-ai image provider (`mock` or `openai`) |
| `TTS_PROVIDER` | No | `mock` | giraf-ai TTS provider (`mock` or `google`) |
| `OPENAI_API_KEY` | No | — | Required if `IMAGE_PROVIDER=openai` |
| `GOOGLE_TTS_CREDENTIALS` | No | — | Required if `TTS_PROVIDER=google` |

## Production Deployment

The default `docker-compose.yml` uses `ASPNETCORE_ENVIRONMENT=Development` for the weekplanner API. For production deployments, override the following:

```yaml
# docker-compose.prod.yml or environment overrides
weekplanner-api:
  environment:
    ASPNETCORE_ENVIRONMENT: Production
    AllowedOrigins__0: https://your-frontend-domain.com
    AllowedOrigins__1: https://another-allowed-origin.com
```

### What changes in Production mode

| Feature | Development | Production |
|---------|-------------|------------|
| CORS | Allow all origins | Only origins in `AllowedOrigins` (fails on startup if missing) |
| API docs | Scalar UI at `/scalar/v1`, OpenAPI at `/openapi/v1.json` | Not available (404) |
| Rate limiting | 60 req/min per IP (active in all environments) | Same |

### Strato deployment (AAU HPC)

On the Strato VM (`130.225.39.225`), set environment variables in the `.env` file or override in the compose:

```bash
# Required for production
ASPNETCORE_ENVIRONMENT=Production
AllowedOrigins__0=http://130.225.39.225:5171
```

The weekplanner API uses `X-Forwarded-For` headers for per-IP rate limiting. If running behind a reverse proxy, ensure it forwards client IPs.

## Useful Commands

```bash
# Rebuild after code changes
docker compose up --build

# Reset databases
docker compose down -v

# View logs for a specific service
docker compose logs -f core-api
```

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

## Useful Commands

```bash
# Rebuild after code changes
docker compose up --build

# Reset databases
docker compose down -v

# View logs for a specific service
docker compose logs -f core-api
```

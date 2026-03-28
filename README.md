# giraf-deploy

Docker Compose orchestration for the full GIRAF stack.

## Services

| Service | Port | Source | Docs (dev) | Health |
|---------|------|--------|------------|--------|
| `core-db` | 5432 (localhost) | PostgreSQL 16 | — | — |
| `core-redis` | 6379 (localhost) | Redis 7 | — | — |
| `core-api` | 8000 | [giraf-core](https://github.com/aau-giraf/giraf-core) | `/api/v1/docs` | `/api/v1/health` |
| `giraf-ai` | 8100 | [giraf-ai](https://github.com/aau-giraf/giraf-ai) | `/docs` | — |
| `weekplanner-db` | 5433 (localhost) | PostgreSQL 15 | — | — |
| `weekplanner-api` | 5171 | [weekplanner](https://github.com/aau-giraf/weekplanner) | `/scalar/v1` | `/health` |

## Prerequisites

- Docker and Docker Compose
- Repos cloned as siblings:

```
GIRAF/
├── giraf-core/
├── giraf-ai/
├── weekplanner/
└── giraf-deploy/       ← you are here
```

## Configuration

Each service reads its own `.env` file. Compose just wires up networking, volumes, and DB connections.

| File | What goes in it |
|------|----------------|
| `giraf-core/.env` | Django settings, JWT secret, DB creds, CORS |
| `giraf-ai/.env` | AI provider keys, JWT secret, debug flag |
| `weekplanner/.env` | JWT secret, ASP.NET environment |
| `giraf-deploy/.env` | Shared DB password only |

Each repo has a `.env.example` — copy and fill in values. Dev vs prod is controlled by what's in these files, not by swapping compose files.

### Dev setup

```bash
# Copy .env.example → .env in each repo and fill in values
cp ../giraf-core/.env.example ../giraf-core/.env
cp ../giraf-ai/.env.example ../giraf-ai/.env
cp ../weekplanner/.env.example ../weekplanner/.env
cp .env.example .env

# At minimum, set JWT_SECRET to the same value in giraf-core, giraf-ai, and weekplanner:
#   JWT_SECRET=<generate with: openssl rand -hex 32>
# Set DJANGO_SETTINGS_MODULE=config.settings.dev in giraf-core/.env
# Set DEBUG=true in giraf-ai/.env
```

### Prod setup

Same files, different values:

```bash
# giraf-core/.env
DJANGO_SETTINGS_MODULE=config.settings.prod
DJANGO_SECRET_KEY=<random>
JWT_SECRET=<shared secret>
ALLOWED_HOSTS=130.225.39.225
CORS_ALLOWED_ORIGINS=http://130.225.39.225:8000

# giraf-ai/.env
JWT_SECRET=<same shared secret>
IMAGE_PROVIDER=gemini
GEMINI_API_KEY=<key>
DEBUG=false

# weekplanner/.env
JWT_SECRET=<same shared secret>
ASPNETCORE_ENVIRONMENT=Production
```

## Quick Start

```bash
# 1. Set up .env files (see above)

# 2. Start everything
docker compose up

# 3. Seed test data (dev mode only)
docker compose exec core-api uv run python manage.py seed_dev_data
./seed_activities.sh

# 4. Run the Flutter frontend
cd ../weekplanner/frontend
flutter run -d chrome
```

## Updating the Deployment

```bash
# Pull latest on all repos
cd ~/giraf
for repo in giraf-core giraf-ai weekplanner giraf-deploy; do
  cd ~/giraf/$repo && git pull
done

# Rebuild and restart
cd ~/giraf/giraf-deploy
docker compose down -v    # -v wipes volumes (only if no valuable data)
docker compose up -d --build

# Re-seed (dev mode only)
docker compose exec core-api uv run python manage.py seed_dev_data
./seed_activities.sh
```

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
docker compose up --build       # Rebuild after code changes
docker compose down -v          # Reset databases
docker compose logs -f core-api # View logs for a service
```

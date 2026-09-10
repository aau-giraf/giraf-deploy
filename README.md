# giraf-deploy

Docker Compose orchestration for the GIRAF stack: giraf-core, giraf-ai and weekplanner.

Visual-tangible-artefacts and foodplanner are **not** part of this stack — run those from their own repos.

## Services

| Service | Port | Source |
|---------|------|--------|
| `core-db` | 5432 | PostgreSQL 16 |
| `core-redis` | 6379 | Redis 7 (cache for giraf-core) |
| `core-api` | 8000 | [giraf-core](https://github.com/aau-giraf/giraf-core) (Django 5) |
| `giraf-ai` | 8100 | [giraf-ai](https://github.com/aau-giraf/giraf-ai) (FastAPI) |
| `weekplanner-db` | 5433 | PostgreSQL 15 |
| `weekplanner-api` | 5171 | [weekplanner](https://github.com/aau-giraf/weekplanner) (ASP.NET, .NET 10) |

Database ports are published on `127.0.0.1` only. The three APIs are published on all interfaces.

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
./setup.sh                # creates the four .env files below
docker compose up --build
docker compose exec core-api uv run python manage.py seed_dev_data
```

`setup.sh` is safe to re-run. It never replaces a `.env` file or a real secret: it reuses a `JWT_SECRET` that is already set rather than generating a conflicting one, and only fills in a `JWT_SECRET` that is still blank or a placeholder from the example file. If two services hold different real secrets it stops and tells you how to start over.

## Environment files

**Compose reads each service's configuration from that service's own repo**, not from `giraf-deploy/.env`. A working stack needs four files:

| File | Holds | Created from |
|------|-------|--------------|
| `giraf-core/.env` | `DJANGO_SECRET_KEY`, `JWT_SECRET`, `POSTGRES_*`, `DJANGO_SETTINGS_MODULE` | `giraf-core/.env.example` |
| `giraf-ai/.env` | `JWT_SECRET`, `IMAGE_PROVIDER`, `TTS_PROVIDER`, provider API keys | `giraf-ai/.env.example` |
| `weekplanner/.env` | `JWT_SECRET`, `ASPNETCORE_ENVIRONMENT` | `weekplanner/.env.example` |
| `giraf-deploy/.env` | `GIRAF_DB_PASSWORD` only | `.env.example` |

The rule that matters: **`JWT_SECRET` must be byte-identical in giraf-core, giraf-ai and weekplanner.** giraf-core issues the tokens; the other two validate them locally with the same key. Nothing checks this at startup — a mismatch surfaces as a 401 later.

Setting `JWT_SECRET`, `DJANGO_SECRET_KEY` or a provider key in `giraf-deploy/.env` has no effect — compose does not pass them to any service.

### Values compose overrides

These are set in `docker-compose.yml` and win over whatever is in the service `.env`:

| Service | Overridden |
|---------|-----------|
| core-api | `POSTGRES_HOST`, `POSTGRES_PORT`, `POSTGRES_DB`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, `REDIS_URL`, `GIRAF_AI_URL` |
| weekplanner-api | `ConnectionStrings__DbConnection`, `GirafCore__BaseUrl` |

Database credentials are pinned to the values the `core-db` container is created with, so `POSTGRES_*` in `giraf-core/.env` applies only when running Django directly against the published port.

## Doing without setup.sh

```bash
SECRET=$(openssl rand -hex 32)
cd ..
for r in giraf-core giraf-ai weekplanner giraf-deploy; do cp -n $r/.env.example $r/.env; done
sed -i "s|^JWT_SECRET=.*|JWT_SECRET=$SECRET|" giraf-core/.env giraf-ai/.env weekplanner/.env
sed -i "s|^DJANGO_SECRET_KEY=.*|DJANGO_SECRET_KEY=$(openssl rand -hex 32)|" giraf-core/.env
cd giraf-deploy && docker compose up --build
```

On macOS use `sed -i ''` instead of `sed -i`.

## AI providers

giraf-ai defaults to `mock` for both image generation and TTS, so **local development needs no API keys**. To use a real provider, set it in `giraf-ai/.env`:

| Capability | Provider | Variables |
|------------|----------|-----------|
| Image | OpenAI DALL·E | `IMAGE_PROVIDER=openai_dalle`, `OPENAI_API_KEY` |
| Image | Google Gemini | `IMAGE_PROVIDER=gemini`, `GEMINI_API_KEY` |
| TTS | Google Gemini TTS | `TTS_PROVIDER=gemini_tts`, `GEMINI_API_KEY` |

## Health checks

| Service | Endpoint |
|---------|----------|
| core-api | `http://localhost:8000/api/v1/health` |
| weekplanner-api | `http://localhost:5171/health` |
| giraf-ai | `http://localhost:8100/api/v1/health` |

API docs are served in development only:

| Service | Docs | Gated on |
|---------|------|----------|
| core-api | `/api/v1/docs` | Django `DEBUG` (on under `config.settings.dev`) |
| weekplanner-api | `/scalar/v1` | `ASPNETCORE_ENVIRONMENT=Development` |
| giraf-ai | `/docs` | `DEBUG=true` in `giraf-ai/.env` — **off by default** |

## Troubleshooting

**`env file /path/giraf-core/.env not found`** — compose refuses to start before building anything. You are missing one of the four env files; run `./setup.sh`.

**`ValidationError: jwt_secret ... String should have at least 32 characters`** (giraf-ai) — `JWT_SECRET` is unset or too short in `giraf-ai/.env`. It is required and has no default.

**`KeyError: 'DJANGO_SECRET_KEY'`** (core-api) — core is running production settings. Set `DJANGO_SETTINGS_MODULE=config.settings.dev` in `giraf-core/.env`; the image defaults to `config.settings.prod`, which also forces an HTTPS redirect that breaks plain-HTTP local use.

**`password authentication failed for user "giraf"`** (core-api) — you changed `GIRAF_DB_PASSWORD` after the stack had already run once. The database volume keeps the password the container was first created with; `docker compose down -v` resets it (and destroys the data).

**401 from giraf-ai or weekplanner with a token that core just issued** — the `JWT_SECRET` values differ. Check with:

```bash
grep -h '^JWT_SECRET=' ../{giraf-core,giraf-ai,weekplanner}/.env | sort -u
```

One line means they agree.

## Production

The stack defaults to development settings. For production, set in the service env files:

```bash
# giraf-core/.env
DJANGO_SETTINGS_MODULE=config.settings.prod
ALLOWED_HOSTS=130.225.39.225
CORS_ALLOWED_ORIGINS=http://130.225.39.225:5171
SECURE_SSL_REDIRECT=false        # only if not terminating TLS

# weekplanner/.env
ASPNETCORE_ENVIRONMENT=Production
AllowedOrigins__0=http://130.225.39.225:5171
```

### What changes in production

| Feature | Development | Production |
|---------|-------------|------------|
| CORS | Allow all origins | Only listed origins (weekplanner fails at startup if none) |
| API docs | Served | 404 |
| Django `DEBUG` | On | Off |
| HTTPS redirect | Off | On unless `SECURE_SSL_REDIRECT=false` |
| Rate limiting | 60 req/min per IP | Same |

The weekplanner API uses `X-Forwarded-For` for per-IP rate limiting; a reverse proxy in front of it must forward client IPs.

## Useful Commands

```bash
docker compose up --build          # rebuild after code changes
docker compose down -v             # reset databases (destroys all data)
docker compose logs -f core-api    # follow one service
docker compose ps                  # what is running
```

## Frontend

The weekplanner frontend is **Flutter**, and is run from its own repo rather than by compose:

```bash
cd ../weekplanner/frontend
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run \
  --dart-define=CORE_BASE_URL=http://localhost:8000 \
  --dart-define=WEEKPLANNER_BASE_URL=http://localhost:5171
```

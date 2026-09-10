#!/usr/bin/env bash
# Generate the .env files the GIRAF stack needs for local development.
#
# docker-compose.yml reads each service's configuration from its own repo's
# .env file, so a working local stack needs four of them:
#
#   giraf-core/.env   giraf-ai/.env   weekplanner/.env   giraf-deploy/.env
#
# This script creates any that are missing (from the matching .env.example),
# generates the secrets, and writes the same JWT_SECRET into all three
# services. Existing .env files are left untouched.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SERVICES=(giraf-core giraf-ai weekplanner)
DB_PASSWORD=localdev123

# giraf-ai declares jwt_secret with Field(min_length=32) and refuses to start
# below it, so anything shorter cannot be a working secret. That also rules
# out the placeholders the .env.example files ship with.
MIN_SECRET_LEN=32

# --- checks ----------------------------------------------------------------

missing=()
for repo in "${SERVICES[@]}"; do
  [[ -d "$ROOT/$repo" ]] || missing+=("$repo")
done
if (( ${#missing[@]} )); then
  echo "error: missing sibling repos: ${missing[*]}" >&2
  echo "Clone them next to giraf-deploy in $ROOT and re-run." >&2
  exit 1
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "error: openssl not found — needed to generate secrets." >&2
  exit 1
fi

# --- helpers ---------------------------------------------------------------

# set_var <file> <KEY> <value> — replace KEY's line, or append if absent.
set_var() {
  local file=$1 key=$2 value=$3 tmp
  tmp="$(mktemp)"
  if grep -qE "^[#[:space:]]*${key}=" "$file"; then
    while IFS= read -r line || [[ -n $line ]]; do
      if [[ $line =~ ^[#[:space:]]*${key}= ]]; then
        printf '%s=%s\n' "$key" "$value"
      else
        printf '%s\n' "$line"
      fi
    done < "$file" > "$tmp"
  else
    cat "$file" > "$tmp"
    printf '%s=%s\n' "$key" "$value" >> "$tmp"
  fi
  mv "$tmp" "$file"
}

# ensure_env <repo> — copy .env.example to .env if .env is absent.
# Returns 0 if it created the file, 1 if one already existed.
ensure_env() {
  local repo=$1
  if [[ -f "$ROOT/$repo/.env" ]]; then
    return 1
  fi
  if [[ ! -f "$ROOT/$repo/.env.example" ]]; then
    echo "error: $repo has neither .env nor .env.example" >&2
    exit 1
  fi
  cp "$ROOT/$repo/.env.example" "$ROOT/$repo/.env"
  return 0
}

# --- generate --------------------------------------------------------------

# Reuse a real JWT_SECRET already committed to an existing .env — a partially
# set up tree must end with all three services agreeing, not with a fresh
# secret in whichever file happened to be missing. A blank or too-short value
# is a placeholder, not a secret: it gets replaced rather than propagated.
usable=()
for repo in "${SERVICES[@]}"; do
  [[ -f "$ROOT/$repo/.env" ]] || continue
  value="$(sed -n 's/^JWT_SECRET=//p' "$ROOT/$repo/.env" | tail -n1)"
  (( ${#value} >= MIN_SECRET_LEN )) && usable+=("$value")
done

distinct="$(printf '%s\n' ${usable[@]+"${usable[@]}"} | sort -u | grep -c . || true)"
if (( distinct > 1 )); then
  echo "error: the existing .env files disagree on JWT_SECRET." >&2
  echo >&2
  echo "All of ${SERVICES[*]} must share one value. To start over:" >&2
  echo >&2
  printf '  rm' >&2
  for repo in "${SERVICES[@]}"; do printf ' ../%s/.env' "$repo" >&2; done
  printf '\n  ./setup.sh\n' >&2
  exit 1
fi

if (( distinct == 1 )); then
  JWT_SECRET="${usable[0]}"
  reused=yes
else
  JWT_SECRET="$(openssl rand -hex 32)"
  reused=no
fi
DJANGO_SECRET_KEY="$(openssl rand -hex 32)"

created=()
skipped=()

for repo in "${SERVICES[@]}" giraf-deploy; do
  if ensure_env "$repo"; then
    created+=("$repo")
  else
    skipped+=("$repo")
  fi
done

# Only write secrets into files this run created — never clobber an existing
# .env, which may hold a secret already shared with a running database.
in_created() {
  local needle=$1 item
  for item in ${created[@]+"${created[@]}"}; do
    [[ $item == "$needle" ]] && return 0
  done
  return 1
}

# Write the shared secret into files this run created, and into any existing
# file whose JWT_SECRET is a placeholder. A real secret is never overwritten:
# by this point at most one distinct usable value exists, and it is the one
# being written.
filled=()
for repo in "${SERVICES[@]}"; do
  if ! in_created "$repo"; then
    value="$(sed -n 's/^JWT_SECRET=//p' "$ROOT/$repo/.env" | tail -n1)"
    [[ $value == "$JWT_SECRET" ]] && continue
    filled+=("$repo")
  fi
  set_var "$ROOT/$repo/.env" JWT_SECRET "$JWT_SECRET"
done

if in_created giraf-core; then
  core_env="$ROOT/giraf-core/.env"
  set_var "$core_env" DJANGO_SECRET_KEY "$DJANGO_SECRET_KEY"
  # Compose pins the database credentials for the container. These matter
  # only when running Django directly against the published port, so point
  # them at the same database with the password that container was made with.
  set_var "$core_env" POSTGRES_PASSWORD "$DB_PASSWORD"
  set_var "$core_env" POSTGRES_HOST localhost
  set_var "$core_env" POSTGRES_PORT 5432
  # Dev settings: DEBUG on, permissive CORS, API docs served, no SSL redirect.
  set_var "$core_env" DJANGO_SETTINGS_MODULE config.settings.dev
fi

if in_created giraf-deploy; then
  set_var "$SCRIPT_DIR/.env" GIRAF_DB_PASSWORD "$DB_PASSWORD"
fi

# --- report ----------------------------------------------------------------

echo
if (( ${#created[@]} )); then
  echo "Created:"
  for repo in "${created[@]}"; do echo "  $repo/.env"; done
fi
if (( ${#skipped[@]} )); then
  echo "Already present (left unchanged):"
  for repo in "${skipped[@]}"; do echo "  $repo/.env"; done
fi
if (( ${#filled[@]} )); then
  echo "JWT_SECRET filled in (was blank or a placeholder):"
  for repo in "${filled[@]}"; do echo "  $repo/.env"; done
fi
if [[ $reused == yes ]]; then
  echo
  echo "Reused the JWT_SECRET already set in the existing .env file(s)."
fi

# All three services validate tokens with this key; a mismatch shows up as a
# 401 from giraf-ai or weekplanner rather than as a startup error.
for repo in "${SERVICES[@]}"; do
  value="$(sed -n 's/^JWT_SECRET=//p' "$ROOT/$repo/.env" | tail -n1)"
  if [[ $value != "$JWT_SECRET" ]]; then
    echo >&2
    echo "error: $repo/.env does not have the shared JWT_SECRET." >&2
    echo "Delete it and re-run to regenerate it." >&2
    exit 1
  fi
done

echo
echo "Next:  docker compose up --build"
echo "Then:  docker compose exec core-api uv run python manage.py seed_dev_data"

#!/usr/bin/env bash
# Seed the weekplanner with demo activities for the current week.
# Prerequisites: giraf-core seeded (seed_dev_data), all services running.
set -euo pipefail

CORE_URL="${CORE_URL:-http://localhost:8000}"
WP_URL="${WP_URL:-http://localhost:5171}"
GIRAF_USER="${GIRAF_USER:-anna}"
GIRAF_PASS="${GIRAF_PASS:-devpass123}"

echo "=== Logging in as $GIRAF_USER ==="
TOKEN=$(curl -sf -X POST "$CORE_URL/api/v1/token/pair" \
  -H 'Content-Type: application/json' \
  -d "{\"username\":\"$GIRAF_USER\",\"password\":\"$GIRAF_PASS\"}" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['access'])")
echo "Got JWT token"

AUTH="Authorization: Bearer $TOKEN"

echo "=== Looking up org, citizen, and pictogram IDs ==="
# API returns paginated responses: {"items": [...], "count": N}

ORG_ID=$(curl -sf -H "$AUTH" "$CORE_URL/api/v1/organizations" \
  | python3 -c "import sys,json; print(json.load(sys.stdin)['items'][0]['id'])")
echo "Org ID: $ORG_ID"

CITIZEN_ID=$(curl -sf -H "$AUTH" "$CORE_URL/api/v1/organizations/$ORG_ID/citizens" \
  | python3 -c "import sys,json; c=json.load(sys.stdin)['items'][0]; print(c['id'])")
echo "Citizen ID: $CITIZEN_ID"

# Include org-scoped pictograms with ?organization_id=
PICTOS=$(curl -sf -H "$AUTH" "$CORE_URL/api/v1/pictograms?organization_id=$ORG_ID")
echo "Pictograms:"
echo "$PICTOS" | python3 -c "
import sys, json
for p in json.load(sys.stdin)['items']:
    print(f\"  {p['id']}: {p['name']}\")"

picto_id() {
  echo "$PICTOS" | python3 -c "
import sys, json
for p in json.load(sys.stdin)['items']:
    if p['name'].lower() == '$1'.lower():
        print(p['id']); break
else:
    print(json.load(open('/dev/stdin'))['items'][0]['id'])" 2>/dev/null || \
  echo "$PICTOS" | python3 -c "import sys,json; print(json.load(sys.stdin)['items'][0]['id'])"
}

P_HAPPY=$(picto_id "Happy")
P_EAT=$(picto_id "Eat")
P_BUS=$(picto_id "School Bus")
P_LUNCH=$(picto_id "Lunchroom")
P_SAD=$(picto_id "Sad")

MONDAY=$(date -d "monday this week" +%Y-%m-%d 2>/dev/null || date -d "last monday" +%Y-%m-%d)
echo ""
echo "=== Creating activities for week of $MONDAY ==="

CREATED=()

add() {
  local offset=$1 start=$2 end=$3 pid=$4
  local d=$(date -d "$MONDAY + $offset days" +%Y-%m-%d)
  local r=$(curl -sf -X POST "$WP_URL/weekplan/to-citizen/$CITIZEN_ID" \
    -H 'Content-Type: application/json' -H "$AUTH" \
    -d "{\"date\":\"$d\",\"startTime\":\"$start\",\"endTime\":\"$end\",\"pictogramId\":$pid}")
  local aid=$(echo "$r" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('activityId', d.get('id','?')))")
  echo "  $d $start-$end -> #$aid"
  CREATED+=("$aid")
}

for day in 0 1 2 3 4; do
  echo "--- $(date -d "$MONDAY + $day days" +%A) ---"
  add $day "08:00" "08:30" "$P_BUS"
  add $day "09:00" "10:30" "$P_HAPPY"
  add $day "11:30" "12:15" "$P_EAT"
  add $day "13:00" "14:00" "$P_LUNCH"
done

echo ""
echo "=== Marking a few as completed ==="
for i in 0 1 2; do
  curl -sf -X PUT "$WP_URL/weekplan/activity/${CREATED[$i]}/iscomplete?IsComplete=true" -H "$AUTH" > /dev/null
  echo "  #${CREATED[$i]} completed"
done

echo ""
echo "=== Done! ${#CREATED[@]} activities created ==="

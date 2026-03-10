#!/usr/bin/env bash
# Clears all items from the case_runtime_state DynamoDB table so the portal
# shows only new cases (created after running this script).
#
# Usage:
#   ./scripts/clear-case-runtime-table.sh <table-name> [region]
#   TABLE_NAME=case-triage-dev-case-runtime-state REGION=eu-west-2 ./scripts/clear-case-runtime-table.sh
#
# Table name is usually: <project>-<env>-case-runtime-state
# Example: case-triage-dev-case-runtime-state

set -e

TABLE_NAME="${1:-$TABLE_NAME}"
REGION="${2:-${REGION:-eu-west-2}}"

if [ -z "$TABLE_NAME" ]; then
  echo "Usage: $0 <table-name> [region]"
  echo "   or: TABLE_NAME=xxx REGION=eu-west-2 $0"
  echo ""
  echo "Table name is usually: <project>-<env>-case-runtime-state"
  echo "Example: case-triage-dev-case-runtime-state"
  exit 1
fi

echo "Clearing all items from table: $TABLE_NAME (region: $REGION)"
count=0
NEXT=""

while true; do
  if [ -n "$NEXT" ]; then
    RESP=$(aws dynamodb scan --table-name "$TABLE_NAME" --region "$REGION" \
      --projection-expression "caseId" --output json --max-items 100 --starting-token "$NEXT")
  else
    RESP=$(aws dynamodb scan --table-name "$TABLE_NAME" --region "$REGION" \
      --projection-expression "caseId" --output json --max-items 100)
  fi
  ITEMS=$(echo "$RESP" | jq -c '.Items // []')
  NEXT=$(echo "$RESP" | jq -r '.NextToken // empty')

  if [ "$ITEMS" = "[]" ] || [ -z "$ITEMS" ]; then
    [ -z "$NEXT" ] && break
    continue
  fi

  for id in $(echo "$ITEMS" | jq -r '.[].caseId.S'); do
    [ -z "$id" ] && continue
    aws dynamodb delete-item --table-name "$TABLE_NAME" --region "$REGION" \
      --key "{\"caseId\":{\"S\":\"$id\"}}" >/dev/null 2>&1
    count=$((count + 1))
  done
  echo "  Deleted $count items so far..."
  [ -z "$NEXT" ] && break
done

echo "Done. Table $TABLE_NAME is empty ($count items removed)."
echo "New cases will appear in the portal when you run the intake flow (POST /applications/init, then complete)."

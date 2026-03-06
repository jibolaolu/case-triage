#!/bin/bash
# ============================================================
# deploy_and_init.sh
# One-command fix: deploy schema_init Lambda + run it
# Run from your terraform/ directory
# ============================================================
set -e

REGION="eu-west-2"
PREFIX="case-triage-dev"
FUNCTION_NAME="${PREFIX}-aurora-schema-init"
SRC_DIR="$(dirname "$0")/lambda_src/schema_init"

echo "============================================================"
echo "Step 1: Package and deploy schema_init Lambda"
echo "============================================================"

# Create zip with handler
cd "$SRC_DIR"
zip -q schema_init.zip handler.py
echo "✓ Packaged schema_init.zip"

# Update Lambda code
aws lambda update-function-code \
  --function-name "$FUNCTION_NAME" \
  --zip-file fileb://schema_init.zip \
  --region "$REGION" \
  --query 'FunctionName' \
  --output text
echo "✓ Lambda code updated"

# Wait for update to complete
aws lambda wait function-updated \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION"
echo "✓ Lambda ready"

# Clean up zip
rm schema_init.zip
cd - > /dev/null

echo ""
echo "============================================================"
echo "Step 2: Invoke schema_init to create all Aurora tables"
echo "============================================================"

aws lambda invoke \
  --function-name "$FUNCTION_NAME" \
  --region "$REGION" \
  --log-type Tail \
  /tmp/schema_init_out.json \
  --query 'LogResult' \
  --output text | base64 --decode | grep -E "✓|✗|ERROR|INFO" | tail -20

echo ""
echo "─── Lambda response ───"
cat /tmp/schema_init_out.json | python3 -c "
import json, sys
resp = json.load(sys.stdin)
body = json.loads(resp.get('body', '{}'))
created = body.get('created', [])
failed  = body.get('failed', [])
print(f'Tables/indexes created: {len(created)}')
print(f'Failed statements:      {len(failed)}')
if failed:
    print()
    print('FAILURES:')
    for f in failed:
        print(f'  ✗ {f[\"description\"]}: {f[\"error\"]}')
else:
    print()
    print('✅ Schema init completed successfully')
    print('   All tables, indexes, and seed data created.')
    print()
    print('Next steps:')
    print('  1. Re-run the test generator to submit new cases')
    print('  2. Aurora writes should now succeed')
    print('  3. Query case_events table to trace workflow progress')
"


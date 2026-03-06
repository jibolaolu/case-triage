"""
GET /cases/{caseId}/pack
Reads the case pack JSON directly from S3 and returns it in the response body.
This avoids CORS issues with presigned URLs being fetched from the browser.
"""

import json
import os
import boto3
from boto3.dynamodb.conditions import Key

dynamodb    = boto3.resource("dynamodb")
s3_client   = boto3.client("s3")

TABLE       = os.environ["DYNAMODB_TABLE"]
PACK_BUCKET = os.environ["CASE_PACK_BUCKET"]

S3_KEY_PATTERNS = [
    "case-packs/{case_id}/case_pack.json",
    "cases/{case_id}/case_pack.json",
    "case-packs/{case_id}/summary.json",
    "outputs/{case_id}/case_pack.json",
]

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,x-api-key",
    "Access-Control-Allow-Methods": "GET,OPTIONS",
}


def find_pack_s3_key(case_id):
    # 1. Check DynamoDB for explicit key written by Agent 4
    try:
        table    = dynamodb.Table(TABLE)
        resp     = table.query(KeyConditionExpression=Key("caseId").eq(case_id))
        items    = resp.get("Items", [])
        if not items:
            single = table.get_item(Key={"caseId": case_id})
            item   = single.get("Item")
            if item:
                items = [item]
        for item in items:
            for field in ("casePackS3Key", "case_pack_s3_key", "s3Key", "packS3Key", "outputS3Key"):
                if field in item and item[field]:
                    return str(item[field])
    except Exception as e:
        print(f"DynamoDB lookup error: {e}")

    # 2. Probe known S3 key patterns
    for pattern in S3_KEY_PATTERNS:
        key = pattern.format(case_id=case_id)
        try:
            s3_client.head_object(Bucket=PACK_BUCKET, Key=key)
            print(f"Found case pack at s3://{PACK_BUCKET}/{key}")
            return key
        except Exception:
            continue

    return None


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    path_params = event.get("pathParameters") or {}
    case_id     = path_params.get("caseId") or path_params.get("id", "")

    if not case_id:
        return {
            "statusCode": 400,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": "caseId path parameter required"})
        }

    try:
        s3_key = find_pack_s3_key(case_id)

        if not s3_key:
            return {
                "statusCode": 404,
                "headers": CORS_HEADERS,
                "body": json.dumps({
                    "error": "Case pack not found — pipeline may still be processing",
                    "caseId": case_id
                })
            }

        # Fetch JSON directly from S3 and return in response body
        # This avoids CORS issues with presigned URLs
        response = s3_client.get_object(Bucket=PACK_BUCKET, Key=s3_key)
        pack_data = json.loads(response["Body"].read().decode("utf-8"))

        # Inject metadata
        pack_data["_s3Key"]  = s3_key
        pack_data["caseId"]  = pack_data.get("caseId") or case_id

        return {
            "statusCode": 200,
            "headers": CORS_HEADERS,
            "body": json.dumps(pack_data)
        }

    except Exception as e:
        print(f"ERROR for case {case_id}: {e}")
        return {
            "statusCode": 500,
            "headers": CORS_HEADERS,
            "body": json.dumps({"error": str(e), "caseId": case_id})
        }

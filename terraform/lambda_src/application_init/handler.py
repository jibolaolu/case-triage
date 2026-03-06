"""
ApplicationInit Lambda — POST /applications/init
Layer 2, Step 1A
"""

import json
import os
import boto3
from botocore.config import Config
import logging
from datetime import datetime, timezone
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

dynamodb = boto3.resource("dynamodb")

# KEY FIX: Force regional endpoint for presigned URL generation.
# Without this, boto3 generates URLs using the global s3.amazonaws.com endpoint.
# S3 signs the URL for eu-west-2 but requests resolves to us-east-1 →
# SignatureDoesNotMatch 403.
# Forcing the regional endpoint makes the URL use:
#   case-triage-dev-...-intake.s3.eu-west-2.amazonaws.com
# which routes correctly and signature validates.
AWS_REGION = os.environ.get("AWS_ACCOUNT_REGION", "eu-west-2")

s3_client = boto3.client(
    "s3",
    region_name=AWS_REGION,
    config=Config(
        signature_version="s3v4",
        s3={"addressing_style": "virtual"}
    )
)

DYNAMODB_TABLE    = os.environ["DYNAMODB_TABLE"]
DOCUMENTS_BUCKET  = os.environ["DOCUMENTS_BUCKET"]
PRESIGNED_URL_TTL = int(os.environ.get("PRESIGNED_URL_TTL", "900"))

REQUIRED_DOC_TYPES = [
    "id_proof",
    "bank_statement_jan",
    "bank_statement_dec",
    "bank_statement_nov",
    "tenancy_agreement",
]


def lambda_handler(event, context):
    logger.info("ApplicationInit invoked")

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    required = ["caseId", "orgId", "caseType", "submissionType", "submittedAt"]
    missing  = [f for f in required if not body.get(f)]
    if missing:
        return _response(400, {"error": f"Missing required fields: {missing}"})

    valid_case_types = {"hardship-fund", "housing-support", "emergency-grant"}
    if body["caseType"] not in valid_case_types:
        return _response(400, {"error": f"Invalid caseType. Must be one of: {valid_case_types}"})

    case_id         = body["caseId"]
    org_id          = body["orgId"]
    case_type       = body["caseType"]
    submission_type = body["submissionType"]
    now             = datetime.now(timezone.utc).isoformat()

    # Write runtime state to DynamoDB
    table = dynamodb.Table(DYNAMODB_TABLE)
    try:
        table.put_item(
            Item={
                "caseId":             case_id,
                "orgId":              org_id,
                "caseType":           case_type,
                "submissionType":     submission_type,
                "status":             "AWAITING_DOCUMENTS",
                "policyVersion":      1,
                "applicationVersion": 1,
                "createdAt":          now,
                "updatedAt":          now,
            },
            ConditionExpression="attribute_not_exists(caseId)"
        )
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _response(409, {"error": f"Case {case_id} already exists"})
        logger.error("DynamoDB write failed: %s", e)
        return _response(500, {"error": "Failed to initialise case"})

    # Generate presigned URLs using regional endpoint
    # No ContentType in Params — avoids SignatureDoesNotMatch if caller
    # sends a different or missing Content-Type header
    upload_urls = {}
    for doc_type in REQUIRED_DOC_TYPES:
        s3_key = f"{org_id}/{case_type}/{case_id}/documents/{doc_type}.pdf"
        try:
            url = s3_client.generate_presigned_url(
                "put_object",
                Params={
                    "Bucket": DOCUMENTS_BUCKET,
                    "Key":    s3_key,
                },
                ExpiresIn=PRESIGNED_URL_TTL
            )
            upload_urls[doc_type] = url
        except ClientError as e:
            logger.error("Failed to generate presigned URL for %s: %s", doc_type, e)
            return _response(500, {"error": "Failed to generate upload URLs"})

    logger.info("Case %s initialised. Status: AWAITING_DOCUMENTS", case_id)

    return _response(200, {
        "caseId":        case_id,
        "status":        "AWAITING_DOCUMENTS",
        "policyVersion": 1,
        "uploadUrls":    upload_urls,
        "expiresIn":     PRESIGNED_URL_TTL,
    })


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": {
            "Content-Type":              "application/json",
            "X-Content-Type-Options":    "nosniff",
            "Strict-Transport-Security": "max-age=31536000; includeSubDomains",
        },
        "body": json.dumps(body)
    }
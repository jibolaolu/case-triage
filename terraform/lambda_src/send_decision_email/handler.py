"""
POST /cases/{caseId}/email - Send decision notification email via SES.
Body: { subject, body, toAddress, toName, decision }
Env vars: SENDER_EMAIL, AUDIT_TRAIL_TABLE, DYNAMODB_TABLE
"""

import json
import os
import boto3
from datetime import datetime, timezone

ses = boto3.client("ses")
dynamodb = boto3.resource("dynamodb")

SENDER_EMAIL = os.environ["SENDER_EMAIL"]
AUDIT_TRAIL_TABLE = os.environ["AUDIT_TRAIL_TABLE"]
DYNAMODB_TABLE = os.environ["DYNAMODB_TABLE"]

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,x-api-key",
    "Access-Control-Allow-Methods": "POST,OPTIONS",
}


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    path_params = event.get("pathParameters") or {}
    case_id = path_params.get("caseId", "")

    if not case_id:
        return _response(400, {"error": "caseId path parameter required"})

    try:
        body = json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return _response(400, {"error": "Invalid JSON body"})

    subject = body.get("subject")
    body_text = body.get("body")
    to_address = body.get("toAddress")
    to_name = body.get("toName")
    decision = body.get("decision")

    if not all([subject, body_text, to_address]):
        return _response(400, {"error": "subject, body, and toAddress are required"})

    try:
        ses.send_email(
            Source=SENDER_EMAIL,
            Destination={"ToAddresses": [to_address]},
            Message={
                "Subject": {"Data": subject, "Charset": "UTF-8"},
                "Body": {
                    "Text": {"Data": body_text, "Charset": "UTF-8"},
                },
            },
        )

        now = datetime.now(timezone.utc).isoformat()
        audit_table = dynamodb.Table(AUDIT_TRAIL_TABLE)
        audit_table.put_item(
            Item={
                "caseId": case_id,
                "timestamp": now,
                "action": "DECISION_EMAIL_SENT",
                "toAddress": to_address,
                "toName": to_name or "",
                "decision": decision or "",
                "subject": subject,
            }
        )

        return _response(200, {"message": "Email sent successfully"})

    except Exception as e:
        print(f"ERROR sending email: {e}")
        return _response(500, {"error": str(e)})

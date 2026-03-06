"""
PUT /notifications/{notificationId}/read - Mark notification as read.
Path param: notificationId (base64 of userId#createdAt)
Env: NOTIFICATIONS_TABLE
"""

import base64
import json
import os
import boto3
from botocore.exceptions import ClientError

dynamodb = boto3.resource("dynamodb")

NOTIFICATIONS_TABLE = os.environ["NOTIFICATIONS_TABLE"]

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,x-api-key",
    "Access-Control-Allow-Methods": "PUT,OPTIONS",
}


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    path_params = event.get("pathParameters") or {}
    notification_id = path_params.get("notificationId", "")

    if not notification_id:
        return _response(400, {"error": "notificationId path parameter required"})

    try:
        decoded = base64.b64decode(notification_id).decode("utf-8")
        if "#" not in decoded:
            return _response(400, {"error": "Invalid notificationId format"})
        user_id, created_at = decoded.split("#", 1)
    except Exception as e:
        print(f"Decode error: {e}")
        return _response(400, {"error": "Invalid notificationId format"})

    try:
        table = dynamodb.Table(NOTIFICATIONS_TABLE)
        table.update_item(
            Key={"userId": user_id, "createdAt": created_at},
            UpdateExpression="SET #r = :read",
            ExpressionAttributeNames={"#r": "read"},
            ExpressionAttributeValues={":read": True},
            ConditionExpression="attribute_exists(userId) AND attribute_exists(createdAt)",
        )
        return _response(200, {"message": "Notification marked as read"})
    except ClientError as e:
        if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
            return _response(404, {"error": "Notification not found"})
        raise
    except Exception as e:
        print(f"ERROR: {e}")
        return _response(500, {"error": str(e)})

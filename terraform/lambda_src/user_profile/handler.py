"""
User profile operations. Routes:
- GET /users/me - Read profile from Cognito + Aurora user_preferences
- PUT /users/me - Update profile (Cognito attributes + Aurora preferences)
Env: COGNITO_USER_POOL_ID, AURORA_CLUSTER_ARN, AURORA_SECRET_ARN, AURORA_DATABASE
"""

import json
import os
import boto3

cognito = boto3.client("cognito-idp")
rds_data = boto3.client("rds-data", region_name=os.environ.get("AWS_REGION", "eu-west-2"))

COGNITO_USER_POOL_ID = os.environ["COGNITO_USER_POOL_ID"]
AURORA_CLUSTER_ARN = os.environ["AURORA_CLUSTER_ARN"]
AURORA_SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
AURORA_DATABASE = os.environ["AURORA_DATABASE"]

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,x-api-key",
    "Access-Control-Allow-Methods": "GET,PUT,OPTIONS",
}


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}


def _get_user_id(event):
    """Extract userId from authorizer claims sub or query param."""
    claims = event.get("requestContext", {}).get("authorizer", {}).get("claims", {})
    if isinstance(claims, dict) and claims.get("sub"):
        return claims["sub"]
    params = event.get("queryStringParameters") or {}
    return params.get("userId", "")


def _aurora_query(sql: str):
    resp = rds_data.execute_statement(
        resourceArn=AURORA_CLUSTER_ARN,
        secretArn=AURORA_SECRET_ARN,
        database=AURORA_DATABASE,
        sql=sql,
        formatRecordsAs="JSON",
    )
    return json.loads(resp.get("formattedRecords", "[]"))


def _aurora_execute(sql: str):
    rds_data.execute_statement(
        resourceArn=AURORA_CLUSTER_ARN,
        secretArn=AURORA_SECRET_ARN,
        database=AURORA_DATABASE,
        sql=sql,
    )


def _get_profile(user_id):
    try:
        u = cognito.admin_get_user(UserPoolId=COGNITO_USER_POOL_ID, Username=user_id)
        attrs = {a["Name"]: a["Value"] for a in u.get("UserAttributes", [])}

        email = attrs.get("email", "")
        name = attrs.get("name", "") or f"{attrs.get('given_name', '')} {attrs.get('family_name', '')}".strip() or email
        phone = attrs.get("phone_number", "")
        department = attrs.get("custom:department", "")

        groups = []
        try:
            gr = cognito.admin_list_groups_for_user(
                UserPoolId=COGNITO_USER_POOL_ID, Username=user_id
            )
            groups = [g.get("GroupName", "") for g in gr.get("Groups", [])]
        except Exception:
            pass
        role = groups[0] if groups else ""

        preferences = {"notifications": {}, "theme": "light"}
        try:
            esc_id = user_id.replace("'", "''")
            rows = _aurora_query(
                f"""
                SELECT preferences FROM user_preferences WHERE user_id = '{esc_id}'
                """
            )
            if rows:
                p = rows[0]
                prefs = p.get("preferences")
                if isinstance(prefs, dict):
                    preferences["notifications"] = prefs.get("notifications", {})
                    preferences["theme"] = prefs.get("theme", "light")
                elif isinstance(prefs, str):
                    try:
                        parsed = json.loads(prefs) or {}
                        preferences["notifications"] = parsed.get("notifications", {})
                        preferences["theme"] = parsed.get("theme", "light")
                    except Exception:
                        pass
        except Exception as e:
            print(f"user_preferences lookup failed (table may not exist): {e}")

        return _response(200, {
            "id": user_id,
            "name": name,
            "email": email,
            "role": role,
            "department": department,
            "phone": phone,
            "preferences": preferences,
        })
    except cognito.exceptions.UserNotFoundException:
        return _response(404, {"error": "User not found"})
    except Exception as e:
        print(f"ERROR get profile: {e}")
        return _response(500, {"error": str(e)})


def _update_profile(user_id, body):
    try:
        updates = []
        attrs_to_update = []

        if "name" in body:
            name = str(body["name"])
            attrs_to_update.append({"Name": "name", "Value": name})
        if "phone" in body:
            attrs_to_update.append({"Name": "phone_number", "Value": str(body["phone"])})
        if "department" in body:
            attrs_to_update.append({"Name": "custom:department", "Value": str(body["department"])})

        if attrs_to_update:
            cognito.admin_update_user_attributes(
                UserPoolId=COGNITO_USER_POOL_ID,
                Username=user_id,
                UserAttributes=attrs_to_update,
            )

        preferences = body.get("preferences", {})
        if preferences:
            notifs = preferences.get("notifications", {})
            theme = preferences.get("theme", "light")
            prefs_obj = {"notifications": notifs if isinstance(notifs, dict) else {}, "theme": str(theme)}
            prefs_json = json.dumps(prefs_obj).replace("'", "''")
            esc_id = user_id.replace("'", "''")

            try:
                _aurora_execute(
                    f"""
                    INSERT INTO user_preferences (user_id, preferences, updated_at)
                    VALUES ('{esc_id}', '{prefs_json}'::jsonb, NOW())
                    ON CONFLICT (user_id) DO UPDATE SET
                        preferences = EXCLUDED.preferences,
                        updated_at = NOW()
                    """
                )
            except Exception as e:
                print(f"user_preferences update failed: {e}")

        return _response(200, {"message": "Profile updated successfully"})
    except cognito.exceptions.UserNotFoundException:
        return _response(404, {"error": "User not found"})
    except Exception as e:
        print(f"ERROR update profile: {e}")
        return _response(500, {"error": str(e)})


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    user_id = _get_user_id(event)
    if not user_id:
        return _response(400, {"error": "userId required (from authorizer or query param userId)"})

    method = (
        event.get("requestContext", {}).get("http", {}).get("method")
        or event.get("httpMethod", "")
    )

    if method == "GET":
        return _get_profile(user_id)

    if method == "PUT":
        try:
            body = json.loads(event.get("body", "{}"))
        except json.JSONDecodeError:
            return _response(400, {"error": "Invalid JSON body"})
        return _update_profile(user_id, body)

    return _response(400, {"error": "Unknown operation"})

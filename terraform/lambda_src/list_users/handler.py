"""
GET /admin/users - List all users from Cognito + Aurora.
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
    "Access-Control-Allow-Methods": "GET,OPTIONS",
}


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}


def _aurora_execute(sql: str, params: list = None):
    """Execute SQL via RDS Data API. Returns list of dicts (JSON format)."""
    kwargs = {
        "resourceArn": AURORA_CLUSTER_ARN,
        "secretArn": AURORA_SECRET_ARN,
        "database": AURORA_DATABASE,
        "sql": sql,
        "formatRecordsAs": "JSON",
    }
    if params:
        kwargs["parameters"] = params
    resp = rds_data.execute_statement(**kwargs)
    return json.loads(resp.get("formattedRecords", "[]"))


def _get_attr(attrs, name, default=""):
    for a in attrs:
        if a.get("Name") == name:
            return a.get("Value", default)
    return default


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    try:
        paginator = cognito.get_paginator("list_users")
        cognito_users = []
        for page in paginator.paginate(UserPoolId=COGNITO_USER_POOL_ID):
            cognito_users.extend(page.get("Users", []))

        caseworkers_by_email = {}
        try:
            rows = _aurora_execute(
                "SELECT c.caseworker_id, c.email, c.full_name, c.active, c.created_at, r.role_name "
                "FROM caseworkers c LEFT JOIN roles r ON c.role_id = r.role_id"
            )
            for row in rows:
                if row and len(row) >= 5:
                    email = row[1].get("stringValue", "") if isinstance(row[1], dict) else ""
                    if email:
                        caseworkers_by_email[email] = {
                            "department": "",
                            "role": row[5].get("stringValue", "") if len(row) > 5 and row[5] else "",
                            "created_at": row[4].get("stringValue", "") if isinstance(row[4], dict) else "",
                        }
        except Exception as e:
            print(f"Aurora caseworkers lookup failed (optional): {e}")

        cases_by_caseworker = {}
        try:
            rows = _aurora_execute(
                "SELECT assigned_caseworker::text, COUNT(*) FROM cases "
                "WHERE assigned_caseworker IS NOT NULL GROUP BY assigned_caseworker"
            )
            for row in rows:
                if row and len(row) >= 2:
                    cw_id = row[0].get("stringValue", "") if isinstance(row[0], dict) else str(row[0])
                    count = row[1].get("longValue", 0) if isinstance(row[1], dict) else 0
                    cases_by_caseworker[cw_id] = count
        except Exception as e:
            print(f"Aurora cases count failed (optional): {e}")

        users = []
        for u in cognito_users:
            username = u.get("Username", "")
            attrs = u.get("Attributes", [])
            email = _get_attr(attrs, "email")
            given = _get_attr(attrs, "given_name")
            family = _get_attr(attrs, "family_name")
            name = f"{given} {family}".strip() or email or username
            status = u.get("UserStatus", "UNKNOWN")
            enabled = u.get("Enabled", True)
            created = u.get("UserCreateDate")
            created_str = created.isoformat() if created else ""

            groups = []
            try:
                gr = cognito.admin_list_groups_for_user(
                    UserPoolId=COGNITO_USER_POOL_ID, Username=username
                )
                groups = [g.get("GroupName", "") for g in gr.get("Groups", [])]
            except Exception:
                pass
            role = groups[0] if groups else ""

            cw = caseworkers_by_email.get(email, {})
            department = cw.get("department", "")
            if not role and cw.get("role"):
                role = cw["role"]

            cases_assigned = 0
            if email and cw:
                cw_id = cw.get("caseworker_id")
                if cw_id:
                    cases_assigned = cases_by_caseworker.get(str(cw_id), 0)

            users.append({
                "id": username,
                "name": name,
                "email": email,
                "role": role,
                "status": "ENABLED" if enabled else "DISABLED",
                "department": department,
                "casesAssigned": cases_assigned,
                "lastLogin": "",
                "createdAt": created_str,
            })

        return _response(200, {"users": users})

    except Exception as e:
        print(f"ERROR: {e}")
        return _response(500, {"error": str(e)})

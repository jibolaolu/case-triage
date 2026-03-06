"""
Admin user operations. Routes:
- POST /admin/users - Create user
- PUT /admin/users/{userId}/role - Update role
- PUT /admin/users/{userId}/status - Toggle active
- DELETE /admin/users/{userId} - Delete user
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
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
}


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}


def _aurora_execute(sql: str):
    rds_data.execute_statement(
        resourceArn=AURORA_CLUSTER_ARN,
        secretArn=AURORA_SECRET_ARN,
        database=AURORA_DATABASE,
        sql=sql,
    )


def _get_method(event):
    return (
        event.get("requestContext", {}).get("http", {}).get("method")
        or event.get("httpMethod", "")
    )


def _get_path(event):
    return (
        event.get("requestContext", {}).get("http", {}).get("path")
        or event.get("path", "")
        or event.get("resource", "")
    )


def _get_path_params(event):
    return event.get("pathParameters") or {}


def _parse_body(event):
    try:
        return json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return {}


def _create_user(body):
    email = body.get("email")
    name = body.get("name", "")
    role = body.get("role", "caseworker")
    org_id = body.get("orgId", "")

    if not email:
        return _response(400, {"error": "email is required"})

    valid_roles = ["admin", "caseworker", "manager"]
    if role not in valid_roles:
        return _response(400, {"error": f"role must be one of: {valid_roles}"})

    try:
        cognito.admin_create_user(
            UserPoolId=COGNITO_USER_POOL_ID,
            Username=email,
            UserAttributes=[
                {"Name": "email", "Value": email},
                {"Name": "email_verified", "Value": "true"},
                {"Name": "preferred_username", "Value": email},
            ]
            + ([{"Name": "name", "Value": name}] if name else [])
            + ([{"Name": "custom:orgId", "Value": org_id}] if org_id else []),
            TemporaryPassword=os.environ.get("DEFAULT_TEMP_PASSWORD", "TempPass123!"),
            MessageAction="RESEND",
            DesiredDeliveryMediums=["EMAIL"],
        )

        cognito.admin_add_user_to_group(
            UserPoolId=COGNITO_USER_POOL_ID, Username=email, GroupName=role
        )

        try:
            org_val = f"'{org_id}'" if org_id else "NULL"
            esc_email = email.replace("'", "''")
            esc_name = name.replace("'", "''")
            _aurora_execute(
                f"""
                INSERT INTO caseworkers (email, full_name, org_id, role_id)
                SELECT '{esc_email}', '{esc_name}', {org_val},
                       (SELECT role_id FROM roles WHERE role_name = '{role}' LIMIT 1)
                WHERE NOT EXISTS (SELECT 1 FROM caseworkers WHERE email = '{esc_email}')
                """
            )
        except Exception as e:
            print(f"Aurora caseworkers insert failed (optional): {e}")

        return _response(201, {"message": "User created successfully", "email": email})

    except cognito.exceptions.UsernameExistsException:
        return _response(409, {"error": "User already exists"})
    except Exception as e:
        print(f"ERROR create user: {e}")
        return _response(500, {"error": str(e)})


def _update_role(user_id, body):
    role = body.get("role")
    if not role:
        return _response(400, {"error": "role is required"})

    valid_roles = ["admin", "caseworker", "manager"]
    if role not in valid_roles:
        return _response(400, {"error": f"role must be one of: {valid_roles}"})

    try:
        gr = cognito.admin_list_groups_for_user(
            UserPoolId=COGNITO_USER_POOL_ID, Username=user_id
        )
        for g in gr.get("Groups", []):
            cognito.admin_remove_user_from_group(
                UserPoolId=COGNITO_USER_POOL_ID,
                Username=user_id,
                GroupName=g.get("GroupName", ""),
            )
        cognito.admin_add_user_to_group(
            UserPoolId=COGNITO_USER_POOL_ID, Username=user_id, GroupName=role
        )

        try:
            u = cognito.admin_get_user(UserPoolId=COGNITO_USER_POOL_ID, Username=user_id)
            email = next((a["Value"] for a in u.get("UserAttributes", []) if a["Name"] == "email"), user_id)
            _aurora_execute(
                f"""
                UPDATE caseworkers SET role_id = (SELECT role_id FROM roles WHERE role_name = '{role}' LIMIT 1)
                WHERE email = '{email.replace("'", "''")}'
                """
            )
        except Exception:
            pass

        return _response(200, {"message": "Role updated successfully"})

    except cognito.exceptions.UserNotFoundException:
        return _response(404, {"error": "User not found"})
    except Exception as e:
        print(f"ERROR update role: {e}")
        return _response(500, {"error": str(e)})


def _update_status(user_id, body):
    active = body.get("active")
    if active is None:
        return _response(400, {"error": "active (boolean) is required"})

    try:
        if active:
            cognito.admin_enable_user(
                UserPoolId=COGNITO_USER_POOL_ID, Username=user_id
            )
        else:
            cognito.admin_disable_user(
                UserPoolId=COGNITO_USER_POOL_ID, Username=user_id
            )

        try:
            u = cognito.admin_get_user(UserPoolId=COGNITO_USER_POOL_ID, Username=user_id)
            email = next((a["Value"] for a in u.get("UserAttributes", []) if a["Name"] == "email"), user_id)
            _aurora_execute(
                f"UPDATE caseworkers SET active = {str(active).lower()} WHERE email = '{email.replace("'", "''")}'"
            )
        except Exception:
            pass

        return _response(200, {"message": "Status updated successfully"})

    except cognito.exceptions.UserNotFoundException:
        return _response(404, {"error": "User not found"})
    except Exception as e:
        print(f"ERROR update status: {e}")
        return _response(500, {"error": str(e)})


def _delete_user(user_id):
    try:
        cognito.admin_delete_user(
            UserPoolId=COGNITO_USER_POOL_ID, Username=user_id
        )

        try:
            u = cognito.admin_get_user(UserPoolId=COGNITO_USER_POOL_ID, Username=user_id)
            email = next((a["Value"] for a in u.get("UserAttributes", []) if a["Name"] == "email"), user_id)
            _aurora_execute(
                f"UPDATE caseworkers SET active = FALSE WHERE email = '{email.replace("'", "''")}'"
            )
        except Exception:
            pass

        return _response(200, {"message": "User deleted successfully"})

    except cognito.exceptions.UserNotFoundException:
        return _response(404, {"error": "User not found"})
    except Exception as e:
        print(f"ERROR delete user: {e}")
        return _response(500, {"error": str(e)})


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    method = _get_method(event)
    path = _get_path(event)
    path_params = _get_path_params(event)
    user_id = path_params.get("userId", "")

    if method == "POST" and ("/admin/users" in path or path == "/admin/users"):
        body = _parse_body(event)
        return _create_user(body)

    if method == "PUT" and user_id:
        body = _parse_body(event)
        if "/role" in path:
            return _update_role(user_id, body)
        if "/status" in path:
            return _update_status(user_id, body)

    if method == "DELETE" and user_id:
        return _delete_user(user_id)

    return _response(400, {"error": "Unknown operation"})

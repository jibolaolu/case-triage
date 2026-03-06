"""
Admin policy operations. Routes:
- GET /admin/policies - List policies
- GET /admin/policies/{policyId} - Get single policy with rules
- POST /admin/policies - Create policy
- PUT /admin/policies/{policyId} - Update policy
- DELETE /admin/policies/{policyId} - Soft delete
Env: AURORA_CLUSTER_ARN, AURORA_SECRET_ARN, AURORA_DATABASE, DOCUMENTS_BUCKET
"""

import json
import os
import boto3

rds_data = boto3.client("rds-data", region_name=os.environ.get("AWS_REGION", "eu-west-2"))

AURORA_CLUSTER_ARN = os.environ["AURORA_CLUSTER_ARN"]
AURORA_SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
AURORA_DATABASE = os.environ["AURORA_DATABASE"]
DOCUMENTS_BUCKET = os.environ.get("DOCUMENTS_BUCKET", "")

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization,x-api-key",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
}


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body)}


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


def _get_method(event):
    return (
        event.get("requestContext", {}).get("http", {}).get("method")
        or event.get("httpMethod", "")
    )


def _get_path_params(event):
    return event.get("pathParameters") or {}


def _parse_body(event):
    try:
        return json.loads(event.get("body", "{}"))
    except json.JSONDecodeError:
        return {}


def _list_policies():
    try:
        rows = _aurora_query(
            """
            SELECT p.policy_id, p.version, p.org_id, p.case_type, p.sub_type, p.status,
                   p.effective_date, p.retired_date, p.created_by, p.created_at
            FROM policies p
            WHERE p.status != 'deleted'
            ORDER BY p.org_id, p.case_type, p.version
            """
        )
        policies = []
        for r in rows:
            policies.append({
                "id": str(r.get("policy_id", "")),
                "version": r.get("version"),
                "orgId": r.get("org_id", ""),
                "caseType": r.get("case_type", ""),
                "subType": r.get("sub_type", ""),
                "status": r.get("status", ""),
                "effectiveDate": str(r.get("effective_date", "")) if r.get("effective_date") else "",
                "retiredDate": str(r.get("retired_date", "")) if r.get("retired_date") else "",
                "createdBy": r.get("created_by", ""),
                "createdAt": str(r.get("created_at", "")) if r.get("created_at") else "",
            })
        return _response(200, {"policies": policies})
    except Exception as e:
        print(f"ERROR list policies: {e}")
        return _response(500, {"error": str(e)})


def _get_policy(policy_id):
    try:
        esc_id = policy_id.replace("'", "''")
        rows = _aurora_query(
            f"""
            SELECT p.policy_id, p.version, p.org_id, p.case_type, p.sub_type, p.status,
                   p.effective_date, p.retired_date, p.created_by, p.created_at
            FROM policies p
            WHERE p.policy_id = '{esc_id}'::uuid AND p.status != 'deleted'
            """
        )
        if not rows:
            return _response(404, {"error": "Policy not found"})

        p = rows[0]
        policy = {
            "id": str(p.get("policy_id", "")),
            "version": p.get("version"),
            "orgId": p.get("org_id", ""),
            "caseType": p.get("case_type", ""),
            "subType": p.get("sub_type", ""),
            "status": p.get("status", ""),
            "effectiveDate": str(p.get("effective_date", "")) if p.get("effective_date") else "",
            "retiredDate": str(p.get("retired_date", "")) if p.get("retired_date") else "",
            "createdBy": p.get("created_by", ""),
            "createdAt": str(p.get("created_at", "")) if p.get("created_at") else "",
            "documents": [],
            "rules": [],
        }

        docs = _aurora_query(
            f"""
            SELECT doc_id, document_type, mandatory, accepted_formats
            FROM policy_documents WHERE policy_id = '{esc_id}'::uuid
            """
        )
        for d in docs:
            policy["documents"].append({
                "id": str(d.get("doc_id", "")),
                "documentType": d.get("document_type", ""),
                "mandatory": d.get("mandatory", True),
                "acceptedFormats": d.get("accepted_formats", ["pdf"]),
            })

        rules = _aurora_query(
            f"""
            SELECT rule_id, rule_name, field_name, operator, comparison_value,
                   is_blocking, description, sort_order
            FROM policy_rules WHERE policy_id = '{esc_id}'::uuid ORDER BY sort_order
            """
        )
        for r in rules:
            policy["rules"].append({
                "id": str(r.get("rule_id", "")),
                "ruleName": r.get("rule_name", ""),
                "fieldName": r.get("field_name", ""),
                "operator": r.get("operator", ""),
                "comparisonValue": r.get("comparison_value", {}),
                "isBlocking": r.get("is_blocking", True),
                "description": r.get("description", ""),
                "sortOrder": r.get("sort_order", 0),
            })

        return _response(200, policy)
    except Exception as e:
        print(f"ERROR get policy: {e}")
        return _response(500, {"error": str(e)})


def _create_policy(body):
    org_id = body.get("orgId", "")
    case_type = body.get("caseType", "")
    sub_type = body.get("subType", "")
    status = body.get("status", "draft")
    created_by = body.get("createdBy", "")

    if not org_id or not case_type:
        return _response(400, {"error": "orgId and caseType are required"})

    try:
        esc_org = org_id.replace("'", "''")
        esc_ct = case_type.replace("'", "''")
        sub_val = f"'{sub_type.replace("'", "''")}'" if sub_type else "NULL"
        cb_val = f"'{created_by.replace("'", "''")}'" if created_by else "NULL"

        version_rows = _aurora_query(
            f"SELECT COALESCE(MAX(version), 0) + 1 AS v FROM policies WHERE org_id = '{esc_org}' AND case_type = '{esc_ct}'"
        )
        version = version_rows[0]["v"] if version_rows else 1

        _aurora_execute(
            f"""
            INSERT INTO policies (org_id, case_type, version, sub_type, status, created_by)
            VALUES ('{esc_org}', '{esc_ct}', {version}, {sub_val}, '{status}', {cb_val})
            """
        )
        rows = _aurora_query(
            f"""
            SELECT policy_id FROM policies
            WHERE org_id = '{esc_org}' AND case_type = '{esc_ct}'
            ORDER BY created_at DESC LIMIT 1
            """
        )
        policy_id = str(rows[0]["policy_id"]) if rows else ""
        return _response(201, {"message": "Policy created", "policyId": policy_id})
    except Exception as e:
        print(f"ERROR create policy: {e}")
        return _response(500, {"error": str(e)})


def _update_policy(policy_id, body):
    status = body.get("status")
    effective_date = body.get("effectiveDate")
    retired_date = body.get("retiredDate")

    try:
        esc_id = policy_id.replace("'", "''")
        updates = []
        if status is not None:
            updates.append(f"status = '{status.replace("'", "''")}'")
        if effective_date is not None:
            updates.append(f"effective_date = '{effective_date}'")
        if retired_date is not None:
            updates.append(f"retired_date = '{retired_date}'")

        if not updates:
            return _response(400, {"error": "No fields to update"})

        _aurora_execute(
            f"""
            UPDATE policies SET {', '.join(updates)}
            WHERE policy_id = '{esc_id}'::uuid AND status != 'deleted'
            """
        )
        return _response(200, {"message": "Policy updated successfully"})
    except Exception as e:
        print(f"ERROR update policy: {e}")
        return _response(500, {"error": str(e)})


def _delete_policy(policy_id):
    try:
        esc_id = policy_id.replace("'", "''")
        _aurora_execute(
            f"UPDATE policies SET status = 'deleted' WHERE policy_id = '{esc_id}'::uuid"
        )
        return _response(200, {"message": "Policy deleted successfully"})
    except Exception as e:
        print(f"ERROR delete policy: {e}")
        return _response(500, {"error": str(e)})


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    method = _get_method(event)
    path_params = _get_path_params(event)
    policy_id = path_params.get("policyId", "")

    if method == "GET" and not policy_id:
        return _list_policies()

    if method == "GET" and policy_id:
        return _get_policy(policy_id)

    if method == "POST" and not policy_id:
        return _create_policy(_parse_body(event))

    if method == "PUT" and policy_id:
        return _update_policy(policy_id, _parse_body(event))

    if method == "DELETE" and policy_id:
        return _delete_policy(policy_id)

    return _response(400, {"error": "Unknown operation"})

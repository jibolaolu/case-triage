"""
GET /cases/{caseId} - Full case detail from DynamoDB + Aurora.
Combines: DynamoDB metadata, Aurora cases/documents/extracted_data/
eval_outcomes/case_summaries/validation_results, presigned S3 URLs, audit trail.
"""

import json
import os
import boto3
from boto3.dynamodb.conditions import Key
from decimal import Decimal

dynamodb = boto3.resource("dynamodb")
rds_data = boto3.client("rds-data")
s3_client = boto3.client("s3")

TABLE = os.environ["DYNAMODB_TABLE"]
AUDIT_TRAIL_TABLE = os.environ["AUDIT_TRAIL_TABLE"]
AURORA_CLUSTER_ARN = os.environ["AURORA_CLUSTER_ARN"]
AURORA_SECRET_ARN = os.environ["AURORA_SECRET_ARN"]
AURORA_DATABASE = os.environ["AURORA_DATABASE"]
DOCUMENTS_BUCKET = os.environ["DOCUMENTS_BUCKET"]
PRESIGN_TTL = 900

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "Content-Type,Authorization",
}


class DecimalEncoder(json.JSONEncoder):
    def default(self, obj):
        if isinstance(obj, Decimal):
            return int(obj) if obj % 1 == 0 else float(obj)
        return super().default(obj)


def _response(status_code: int, body: dict):
    return {"statusCode": status_code, "headers": CORS_HEADERS, "body": json.dumps(body, cls=DecimalEncoder)}


def _rds_param(name: str, value) -> dict:
    if value is None:
        return {"name": name, "value": {"isNull": True}}
    if isinstance(value, bool):
        return {"name": name, "value": {"booleanValue": value}}
    if isinstance(value, int):
        return {"name": name, "value": {"longValue": value}}
    if isinstance(value, float):
        return {"name": name, "value": {"doubleValue": value}}
    return {"name": name, "value": {"stringValue": str(value)}}


def _rds_query(sql: str, params: list = None) -> list:
    kwargs = {
        "resourceArn": AURORA_CLUSTER_ARN,
        "secretArn": AURORA_SECRET_ARN,
        "database": AURORA_DATABASE,
        "sql": sql,
    }
    if params:
        kwargs["parameters"] = params
    try:
        resp = rds_data.execute_statement(**kwargs)
        cols = [c["name"] for c in resp.get("columnMetadata", [])]
        rows = []
        for rec in resp.get("records", []):
            row = {}
            for col, field in zip(cols, rec):
                # Handle isNull explicitly
                if "isNull" in field and field["isNull"]:
                    row[col] = None
                else:
                    row[col] = next(iter(field.values()))
            rows.append(row)
        print(f"RDS query OK: {sql[:60]} → {len(rows)} rows")
        return rows
    except Exception as e:
        print(f"RDS QUERY FAILED: {sql[:60]} | ERROR: {str(e)}")
        return []


def _presign_url(bucket: str, key: str, ttl: int = PRESIGN_TTL) -> str:
    return s3_client.generate_presigned_url("get_object", Params={"Bucket": bucket, "Key": key}, ExpiresIn=ttl)


def lambda_handler(event, context):
    if event.get("requestContext", {}).get("http", {}).get("method") == "OPTIONS":
        return {"statusCode": 200, "headers": CORS_HEADERS, "body": ""}

    path_params = event.get("pathParameters") or {}
    case_id = path_params.get("caseId") or path_params.get("id", "")

    if not case_id:
        return _response(400, {"error": "caseId required"})

    try:
        # 1. DynamoDB case metadata
        table = dynamodb.Table(TABLE)
        resp = table.get_item(Key={"caseId": case_id})
        item = resp.get("Item")
        if not item:
            return _response(404, {"error": f"Case {case_id} not found"})

        # 2. Aurora: cases (extended info)
        case_rows = _rds_query(
            "SELECT case_type, sub_type, applicant_reference, assigned_caseworker, created_at, updated_at FROM cases WHERE case_id = :cid",
            [_rds_param("cid", case_id)],
        )
        case_row = case_rows[0] if case_rows else {}

        # 3. Aurora: documents
        doc_rows = _rds_query(
            "SELECT document_id, document_type, s3_key, s3_bucket FROM documents WHERE case_id = :cid",
            [_rds_param("cid", case_id)],
        )
        documents = []
        for d in doc_rows:
            s3_key = d.get("s3_key") or ""
            s3_bucket = d.get("s3_bucket") or DOCUMENTS_BUCKET
            view_url = _presign_url(s3_bucket, s3_key) if s3_key else ""
            documents.append({
                "id": str(d.get("document_id", "")),
                "name": d.get("document_type", ""),
                "type": d.get("document_type", ""),
                "uploadedAt": "",
                "viewUrl": view_url,
                "downloadUrl": view_url,
            })

        # 4. Aurora: extracted_data
        ext_rows = _rds_query(
            "SELECT field_name, field_value, confidence FROM extracted_data WHERE case_id = :cid",
            [_rds_param("cid", case_id)],
        )
        extracted_data = {r.get("field_name", ""): r.get("field_value") for r in ext_rows if r.get("field_name")}

        # 4b. Fallback: merge DynamoDB item's extractedData (pipeline writes nested JSON by doc type)
        ddb_extracted = item.get("extractedData")
        if ddb_extracted:
            try:
                parsed = json.loads(ddb_extracted) if isinstance(ddb_extracted, str) else ddb_extracted
                if isinstance(parsed, dict):
                    for doc_type, fields in parsed.items():
                        if isinstance(fields, dict) and "error" not in fields:
                            for k, v in fields.items():
                                if k and v is not None and str(v).strip() and k not in extracted_data:
                                    extracted_data[k] = str(v).strip()
            except (json.JSONDecodeError, TypeError):
                pass

        def _norm_key(k):
            if not k:
                return ""
            return str(k).lower().replace(" ", "_").replace("-", "_")

        def _from_extracted(*keys):
            # Try exact keys first
            for k in keys:
                v = extracted_data.get(k)
                if v is not None and str(v).strip():
                    return str(v).strip()
            # Then try normalized (e.g. "Full Name" -> "full_name")
            norm_map = {_norm_key(k): (k, v) for k, v in extracted_data.items() if k and v}
            for k in keys:
                n = _norm_key(k)
                if n in norm_map:
                    _, v = norm_map[n]
                    if v and str(v).strip():
                        return str(v).strip()
            return None

        # Map extracted_data to top-level applicant fields for portal display (name/DOB visible to caseworker)
        applicant_name = (item.get("applicantName") or "").strip() or _from_extracted(
            "full_name", "applicant_name", "name", "applicantName", "Full Name", "full name", "Applicant Name"
        )
        applicant_email = (item.get("applicantEmail") or "").strip() or _from_extracted(
            "email", "applicant_email", "applicantEmail", "Email"
        )
        ni_number = _from_extracted(
            "ni_number", "nino", "national_insurance_number", "nationalInsuranceNumber", "NI Number", "ni number"
        )
        dob = _from_extracted(
            "dob", "date_of_birth", "dateOfBirth", "birth_date", "Date of Birth", "date of birth", "DOB"
        )
        phone = _from_extracted(
            "phone", "phone_number", "telephone", "mobile", "contact_number", "Phone", "phone number"
        )

        # 5. Aurora: eval_outcomes (policy evaluation)
        eval_rows = _rds_query(
            "SELECT rule_id, result, explanation, is_blocking FROM eval_outcomes WHERE case_id = :cid",
            [_rds_param("cid", case_id)],
        )
        rule_evaluations = [
            {"ruleId": str(r.get("rule_id", "")), "passed": r.get("result") == "PASS", "reason": r.get("explanation")}
            for r in eval_rows
        ]

        # 6. Aurora: case_summaries
        sum_rows = _rds_query(
            "SELECT priority, complexity, recommendation, supervisor_review, risk_flags, strengths, concerns, summary_json FROM case_summaries WHERE case_id = :cid",
            [_rds_param("cid", case_id)],
        )
        summary_row = sum_rows[0] if sum_rows else {}
        ai_recommendation = None
        if summary_row.get("recommendation"):
            rec = str(summary_row["recommendation"]).upper()
            if "APPROVE" in rec:
                ai_recommendation = "APPROVE"
            elif "DECLINE" in rec:
                ai_recommendation = "DECLINE"

        # 7. Aurora: validation_results (tech validation)
        val_rows = _rds_query(
            "SELECT document_type, is_valid, failure_reason FROM validation_results WHERE case_id = :cid",
            [_rds_param("cid", case_id)],
        )
        validation_results = [
            {"documentType": r.get("document_type"), "isValid": r.get("is_valid"), "reason": r.get("failure_reason")}
            for r in val_rows
        ]

        # 8. DynamoDB audit trail
        audit_table = dynamodb.Table(AUDIT_TRAIL_TABLE)
        audit_resp = audit_table.query(KeyConditionExpression=Key("caseId").eq(case_id))
        audit_items = audit_resp.get("Items", [])
        audit_trail = []
        for a in sorted(audit_items, key=lambda x: x.get("eventAt", "")):
            action = a.get("action") or (a.get("fromStatus", "") + " -> " + a.get("toStatus", ""))
            detail = a.get("details")
            if isinstance(detail, str):
                try:
                    detail = json.loads(detail) if detail else {}
                except json.JSONDecodeError:
                    detail = {}
            audit_trail.append({"eventAt": a.get("eventAt"), "agent": a.get("agent"), "action": action, "detail": detail or {}})

        # Build CaseDetail matching frontend types
        ai_confidence = item.get("aiConfidence")
        if ai_confidence is not None and isinstance(ai_confidence, Decimal):
            ai_confidence = float(ai_confidence)

        detail = {
            "caseId": case_id,
            "status": item.get("status", ""),
            "priority": item.get("priority", "MEDIUM"),
            "applicantName": applicant_name or "",
            "applicantEmail": applicant_email or "",
            "applicationType": item.get("applicationType") or case_row.get("case_type", ""),
            "assignedTo": item.get("assignedTo", ""),
            "assignedToName": item.get("assignedToName", ""),
            "createdAt": item.get("createdAt", ""),
            "updatedAt": item.get("updatedAt", ""),
            "submittedAt": item.get("createdAt", ""),
            "aiConfidence": ai_confidence,
            "aiRecommendation": ai_recommendation,
            "notes": summary_row.get("recommendation"),
            "documents": documents,
            "extractedData": extracted_data,
            "ruleEvaluations": rule_evaluations,
            "validationResults": validation_results,
            "auditTrail": audit_trail,
        }
        if ni_number is not None:
            detail["niNumber"] = ni_number
        if dob is not None:
            detail["dob"] = dob
        if phone is not None:
            detail["phone"] = phone

        return _response(200, detail)

    except Exception as e:
        print(f"ERROR for case {case_id}: {e}")
        return _response(500, {"error": str(e), "caseId": case_id})

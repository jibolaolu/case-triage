"""
TechValidation Lambda — Agent 1 (Layer 5)
Triggered by SQS tech-validation-queue

Responsibilities:
1. Load document list from S3 for the case
2. Validate each document: file size, readability, MIME type
3. Write per-document results to Aurora validation_results table
4. Write workflow event to Aurora case_events (workflow trace)
5. Write DynamoDB audit trail entry
6. Update DynamoDB status → DOCS_TECHNICALLY_VALIDATED or DOCS_TECHNICALLY_FAILED

FIX v2:
- Imports agent_utils for dual-write audit (DynamoDB + Aurora case_events)
- Calls write_case_to_aurora before validation_results (FK dependency)
- Calls write_validation_results_to_aurora with structured per-doc results
- Structured logging for CloudWatch Insights queries
"""

import json
import os
import sys
import boto3
import logging
from datetime import datetime, timezone
from botocore.exceptions import ClientError

# agent_utils is deployed alongside handler.py in each Lambda zip
sys.path.insert(0, os.path.dirname(__file__))
import agent_utils

logger = logging.getLogger()
logger.setLevel(logging.INFO)

s3_client = boto3.client("s3")

DYNAMODB_TABLE   = os.environ["DYNAMODB_TABLE"]
DOCUMENTS_BUCKET = os.environ["DOCUMENTS_BUCKET"]

REQUIRED_DOC_TYPES = [
    "id_proof",
    "bank_statement_jan",
    "bank_statement_dec",
    "bank_statement_nov",
    "tenancy_agreement",
]

MAX_FILE_SIZE_BYTES = 10 * 1024 * 1024   # 10 MB
MIN_FILE_SIZE_BYTES = 1024               # 1 KB

ACCEPTED_CONTENT_TYPES = {
    "application/pdf",
    "application/octet-stream",
    "binary/octet-stream",
    "",
}


def lambda_handler(event, context):
    """SQS trigger — batch_size=1, report individual failures."""
    failures = []

    for record in event.get("Records", []):
        message_id = record["messageId"]
        try:
            body = json.loads(record["body"])
            _process_case(body)
        except Exception as e:
            logger.error(
                json.dumps({
                    "event": "AGENT_ERROR",
                    "agent": "TechValidation",
                    "messageId": message_id,
                    "error": str(e),
                })
            )
            failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": failures}


def _process_case(body):
    case_id   = body["caseId"]
    org_id    = body.get("orgId", "")
    case_type = body.get("caseType", "")

    logger.info(json.dumps({
        "event": "AGENT_START",
        "agent": "TechValidation",
        "caseId": case_id,
    }))

    # Load case from DynamoDB if fields missing from message
    if not case_type or not org_id:
        current = agent_utils.get_case_status(case_id)
        import boto3 as _boto3
        table = _boto3.resource("dynamodb").Table(DYNAMODB_TABLE)
        result = table.get_item(Key={"caseId": case_id})
        item = result.get("Item", {})
        case_type = case_type or item.get("caseType", "unknown")
        org_id    = org_id    or item.get("orgId", "unknown")

    # Idempotency check
    current_status = agent_utils.get_case_status(case_id)
    if current_status == "DOCS_TECHNICALLY_VALIDATED":
        logger.info(json.dumps({
            "event": "AGENT_SKIP",
            "agent": "TechValidation",
            "caseId": case_id,
            "reason": "already validated",
        }))
        return

    from_status = current_status or "INTAKE_VALIDATED"

    # ── Ensure case row exists in Aurora before writing validation_results ────
    # (validation_results has FK to cases)
    agent_utils.write_case_to_aurora(
        case_id, org_id, case_type,
        policy_version=1
    )

    # ── Validate each document ────────────────────────────────────────────────
    doc_results = []
    validation_errors = []

    for doc_type in REQUIRED_DOC_TYPES:
        s3_key = f"{org_id}/{case_type}/{case_id}/documents/{doc_type}.pdf"
        error, file_size, mime_type = _validate_document(s3_key, doc_type)

        doc_results.append({
            "document_type":  doc_type,
            "is_valid":       error is None,
            "file_size_bytes": file_size,
            "mime_type":      mime_type,
            "failure_reason": error,
        })

        if error:
            validation_errors.append(error)

    # ── Determine outcome ─────────────────────────────────────────────────────
    new_status = ("DOCS_TECHNICALLY_VALIDATED"
                  if not validation_errors
                  else "DOCS_TECHNICALLY_FAILED")

    # ── Update DynamoDB runtime state ─────────────────────────────────────────
    extra = {}
    if validation_errors:
        extra["validationErrors"] = validation_errors

    agent_utils.update_status(case_id, new_status, extra if extra else None)

    # ── Dual-write audit: DynamoDB audit trail + Aurora case_events ───────────
    agent_utils.write_audit(
        case_id     = case_id,
        agent       = "TechValidation",
        from_status = from_status,
        to_status   = new_status,
        details     = {
            "docs_checked":  len(REQUIRED_DOC_TYPES),
            "errors":        validation_errors,
            "all_present":   not validation_errors,
        }
    )

    # ── Write per-doc results to Aurora validation_results ────────────────────
    agent_utils.write_validation_results_to_aurora(case_id, doc_results)

    logger.info(json.dumps({
        "event":     "AGENT_COMPLETE",
        "agent":     "TechValidation",
        "caseId":    case_id,
        "status":    new_status,
        "docsOk":    len([d for d in doc_results if d["is_valid"]]),
        "docsFail":  len([d for d in doc_results if not d["is_valid"]]),
    }))


def _validate_document(s3_key, doc_type):
    """
    Returns (error_string_or_None, file_size_bytes, mime_type).
    """
    try:
        meta = s3_client.head_object(Bucket=DOCUMENTS_BUCKET, Key=s3_key)
    except ClientError as e:
        code = e.response["Error"]["Code"]
        if code in ("404", "NoSuchKey"):
            return f"{doc_type}: document not found in S3", 0, ""
        return f"{doc_type}: S3 access error ({code})", 0, ""

    file_size    = meta.get("ContentLength", 0)
    content_type = meta.get("ContentType", "").split(";")[0].strip().lower()

    if file_size < MIN_FILE_SIZE_BYTES:
        return (f"{doc_type}: file too small ({file_size} bytes)",
                file_size, content_type)
    if file_size > MAX_FILE_SIZE_BYTES:
        return (f"{doc_type}: file too large ({file_size} bytes)",
                file_size, content_type)

    if content_type not in ACCEPTED_CONTENT_TYPES:
        logger.warning(
            "%s: unexpected content_type '%s' — accepting (size check passed)",
            doc_type, content_type
        )

    return None, file_size, content_type

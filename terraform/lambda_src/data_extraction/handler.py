"""
DataExtraction Lambda — Agent 2 (Layer 5)
Triggered by SQS extraction-queue

Responsibilities:
1. Load technically validated documents from S3
2. Run Textract OCR on each document
3. Use Bedrock (Claude) to extract structured JSON fields from OCR output
4. Write extracted data to DynamoDB AND Aurora extracted_data table
5. Write workflow event to Aurora case_events (workflow trace)
6. Update status → DATA_EXTRACTED or EXTRACTION_FAILED

FIX v2:
- Imports agent_utils for dual-write audit (DynamoDB + Aurora case_events)
- Calls write_case_to_aurora before extracted_data (FK dependency)
- Calls write_extracted_data_to_aurora with merged field dict
- Structured JSON logging for CloudWatch Insights
"""

import json
import os
import sys
import boto3
import logging
from datetime import datetime, timezone
from botocore.exceptions import ClientError

sys.path.insert(0, os.path.dirname(__file__))
import agent_utils

logger = logging.getLogger()
logger.setLevel(logging.INFO)

import boto3 as _boto3
dynamodb  = _boto3.resource("dynamodb")
s3_client = _boto3.client("s3")
textract  = _boto3.client("textract")
bedrock   = _boto3.client(
    "bedrock-runtime",
    region_name=os.environ.get("AWS_ACCOUNT_REGION", "eu-west-2")
)

DYNAMODB_TABLE   = os.environ["DYNAMODB_TABLE"]
DOCUMENTS_BUCKET = os.environ["DOCUMENTS_BUCKET"]
BEDROCK_MODEL_ID = os.environ.get(
    "BEDROCK_MODEL_ID",
    "anthropic.claude-3-7-sonnet-20250219-v1:0"
)

EXTRACTION_PROMPT = """You are a document data extraction agent for a UK government case triage system.

Extract the following fields from the OCR text below. Return ONLY valid JSON — no explanation, no markdown.

Required fields:
- applicant_name (string)
- date_of_birth (string, YYYY-MM-DD format)
- national_insurance_number (string)
- monthly_income_gbp (number)
- account_balance_gbp (number)
- monthly_rent_gbp (number)
- address (string)
- employment_status (string: employed/unemployed/self-employed)

If a field cannot be found, set it to null. Do not guess or infer values.

OCR TEXT:
{ocr_text}

Return JSON only:"""


def lambda_handler(event, context):
    failures = []

    for record in event.get("Records", []):
        message_id = record["messageId"]
        try:
            body = json.loads(record["body"])
            _process_case(body)
        except Exception as e:
            logger.error(json.dumps({
                "event":     "AGENT_ERROR",
                "agent":     "DataExtraction",
                "messageId": message_id,
                "error":     str(e),
            }))
            failures.append({"itemIdentifier": message_id})

    return {"batchItemFailures": failures}


def _process_case(body):
    case_id   = body["caseId"]
    org_id    = body.get("orgId", "")
    case_type = body.get("caseType", "")

    logger.info(json.dumps({
        "event":  "AGENT_START",
        "agent":  "DataExtraction",
        "caseId": case_id,
    }))

    table = dynamodb.Table(DYNAMODB_TABLE)

    # Idempotency check + load missing fields from DynamoDB
    result = table.get_item(Key={"caseId": case_id})
    case   = result.get("Item", {})
    current_status = case.get("status", "")

    if current_status == "DATA_EXTRACTED":
        logger.info(json.dumps({
            "event":  "AGENT_SKIP",
            "agent":  "DataExtraction",
            "caseId": case_id,
            "reason": "already extracted",
        }))
        return

    from_status = current_status or "DOCS_TECHNICALLY_VALIDATED"
    case_type   = case_type or case.get("caseType", "unknown")
    org_id      = org_id    or case.get("orgId", "unknown")

    # ── Ensure case row exists in Aurora before writing extracted_data ────────
    # (extracted_data has FK to cases)
    agent_utils.write_case_to_aurora(case_id, org_id, case_type, policy_version=1)

    # ── Extract from documents ────────────────────────────────────────────────
    doc_types = ["bank_statement_jan", "id_proof"]
    extracted_data  = {}
    docs_processed  = 0
    docs_with_errors = 0

    for doc_type in doc_types:
        s3_key = f"{org_id}/{case_type}/{case_id}/documents/{doc_type}.pdf"
        try:
            ocr_text = _run_textract(s3_key)
            fields   = _extract_fields_with_bedrock(ocr_text, doc_type)
            extracted_data[doc_type] = fields
            docs_processed += 1
            logger.info(json.dumps({
                "event":    "TEXTRACT_OK",
                "agent":    "DataExtraction",
                "caseId":   case_id,
                "docType":  doc_type,
                "lines":    len(ocr_text.splitlines()),
            }))
        except Exception as e:
            logger.warning(json.dumps({
                "event":   "EXTRACT_FAIL",
                "agent":   "DataExtraction",
                "caseId":  case_id,
                "docType": doc_type,
                "error":   str(e),
            }))
            extracted_data[doc_type] = {"error": str(e)}
            docs_with_errors += 1

    # ── Determine overall status ──────────────────────────────────────────────
    has_errors = any(
        isinstance(v, dict) and "error" in v
        for v in extracted_data.values()
    )
    new_status = "EXTRACTION_FAILED" if has_errors else "DATA_EXTRACTED"

    # ── Update DynamoDB runtime state ─────────────────────────────────────────
    now = datetime.now(timezone.utc).isoformat()
    table.update_item(
        Key={"caseId": case_id},
        UpdateExpression="SET #s = :status, updatedAt = :now, extractedData = :data",
        ExpressionAttributeNames={"#s": "status"},
        ExpressionAttributeValues={
            ":status": new_status,
            ":now":    now,
            ":data":   json.dumps(extracted_data),
        },
    )

    # ── Dual-write audit: DynamoDB audit trail + Aurora case_events ───────────
    agent_utils.write_audit(
        case_id     = case_id,
        agent       = "DataExtraction",
        from_status = from_status,
        to_status   = new_status,
        details     = {
            "docs_processed":  docs_processed,
            "docs_with_errors": docs_with_errors,
            "model":           BEDROCK_MODEL_ID,
        }
    )

    # ── Write merged fields to Aurora extracted_data ──────────────────────────
    # Flatten: merge all doc fields into a single dict, source doc tagged
    merged_fields = {}
    for doc_type, fields in extracted_data.items():
        if isinstance(fields, dict) and "error" not in fields:
            for k, v in fields.items():
                if k not in merged_fields and v is not None:
                    merged_fields[k] = v

    agent_utils.write_extracted_data_to_aurora(case_id, merged_fields)

    logger.info(json.dumps({
        "event":          "AGENT_COMPLETE",
        "agent":          "DataExtraction",
        "caseId":         case_id,
        "status":         new_status,
        "docsProcessed":  docs_processed,
        "fieldsExtracted": len(merged_fields),
    }))


def _run_textract(s3_key):
    """Run Textract on the PDF and return concatenated text lines."""
    response = textract.detect_document_text(
        Document={"S3Object": {"Bucket": DOCUMENTS_BUCKET, "Name": s3_key}}
    )
    blocks = response.get("Blocks", [])
    lines  = [b["Text"] for b in blocks if b["BlockType"] == "LINE"]
    return "\n".join(lines)


def _extract_fields_with_bedrock(ocr_text, doc_type):
    """Use Claude via Bedrock to extract structured fields from OCR text."""
    prompt = EXTRACTION_PROMPT.format(ocr_text=ocr_text[:8000])

    response = bedrock.invoke_model(
        modelId=BEDROCK_MODEL_ID,
        contentType="application/json",
        accept="application/json",
        body=json.dumps({
            "anthropic_version": "bedrock-2023-05-31",
            "max_tokens": 512,
            "messages": [{"role": "user", "content": prompt}]
        })
    )

    raw  = json.loads(response["body"].read())
    text = raw["content"][0]["text"].strip()

    # Strip markdown fences if present
    if text.startswith("```"):
        text = text.split("```")[1]
        if text.startswith("json"):
            text = text[4:]

    return json.loads(text)

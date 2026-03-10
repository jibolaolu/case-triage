/**
 * POST /applications/init – create case, init state, return presigned URLs.
 * Idempotency required. Multi-tenant: orgId from JWT and validated against DB.
 */
import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { PutObjectCommand, getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { S3Client } from '@aws-sdk/client-s3';
import { marshall } from '@aws-sdk/util-dynamodb';
import { getOrgIdFromEvent } from '../../shared/nodejs/tenant.js';
import { getIdempotencyResponse, setIdempotencyResponse, requireIdempotencyKey } from '../../shared/nodejs/idempotency.js';
import { log, addRequestContext } from '../../shared/nodejs/observability.js';
import { query } from '../../shared/nodejs/db.js';

const dynamo = new DynamoDBClient({});
const s3 = new S3Client({});
const TABLE_IDEMPOTENCY = process.env.IDEMPOTENCY_TABLE;
const TABLE_CASE_STATE = process.env.CASE_STATE_TABLE;
const ENVIRONMENT = process.env.ENVIRONMENT || 'dev';

export async function handler(event, context) {
  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return { statusCode: 400, body: JSON.stringify({ error: { code: 'INVALID_JSON', message: 'Invalid JSON body' } }) };
  }

  const idempotencyKey = requireIdempotencyKey(event.headers);
  const cached = await getIdempotencyResponse(TABLE_IDEMPOTENCY, idempotencyKey);
  if (cached) return { statusCode: cached.statusCode, body: cached.body };

  const orgId = getOrgIdFromEvent(event);

  const orgRow = await query('SELECT 1 FROM organisations WHERE organisation_id = $1 AND status = $2', [orgId, 'active']);
  if (!orgRow.rows.length) {
    return { statusCode: 403, body: JSON.stringify({ error: { code: 'FORBIDDEN', message: 'Organisation not found or inactive' } }) };
  }

  const caseTypeId = body.caseType || 'hardship-fund';
  let policyId = body.policyId;
  if (!policyId) {
    const policyRow = await query(
      `SELECT policy_id FROM policies WHERE organisation_id = $1 AND case_type_id = $2 AND status = $3 ORDER BY version DESC LIMIT 1`,
      [orgId, caseTypeId, 'active']
    );
    policyId = policyRow.rows[0]?.policy_id || null;
  }
  if (!policyId) {
    return { statusCode: 400, body: JSON.stringify({ error: { code: 'NO_POLICY', message: 'No active policy for organisation; provide policyId' } }) };
  }

  const caseId = body.caseId ?? `HF-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  const policyVersion = body.policyVersion ?? 1;
  const submissionType = body.submissionType || 'NEW';

  // Extract all applicant fields from manifest
  const applicant      = body.applicant || {};
  const applicantRef   = [applicant.firstName, applicant.lastName].filter(Boolean).join(' ') || null;
  const applicantName  = applicantRef;
  const applicantEmail = applicant.email   || null;
  const applicantPhone = applicant.phone   || null;
  const applicantDob   = applicant.dob     || null;
  const applicantNi    = applicant.nationalInsurance || null;
  const applicantAddr  = applicant.address
    ? JSON.stringify(applicant.address)
    : null;

  await query(
    `INSERT INTO cases (
       case_id, organisation_id, case_type_id, policy_id, policy_version,
       submission_type, applicant_reference, applicant_name, applicant_email,
       applicant_phone, applicant_dob, applicant_ni, applicant_address,
       status, updated_at
     )
     VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, NOW())
     ON CONFLICT (case_id) DO UPDATE SET
       applicant_name    = EXCLUDED.applicant_name,
       applicant_email   = EXCLUDED.applicant_email,
       applicant_phone   = EXCLUDED.applicant_phone,
       applicant_dob     = EXCLUDED.applicant_dob,
       applicant_ni      = EXCLUDED.applicant_ni,
       applicant_address = EXCLUDED.applicant_address,
       updated_at        = NOW()`,
    [
      caseId, orgId, caseTypeId, policyId, policyVersion,
      submissionType, applicantRef, applicantName, applicantEmail,
      applicantPhone, applicantDob, applicantNi, applicantAddr,
      'INTAKE_IN_PROGRESS'
    ]
  );

  const docsToUpload = body['documents-to-upload'] || [];
  const uploadUrls = {};
  const expectedKeys = [];
  const bucket = `${orgId}-${caseTypeId}-applicant-intake-s3-${ENVIRONMENT}`;
  const ts = Date.now();

  for (const doc of docsToUpload) {
    const docType = doc.documentType || doc.document_type || 'document';
    const version = doc.version || 1;
    const ext = (doc.fileName || 'file.pdf').split('.').pop() || 'pdf';
    const key = `${orgId}/${caseTypeId}/${caseId}/documents/${docType}-${ts}-v${version}.${ext}`;
    expectedKeys.push({ key, documentType: docType, version });
    const cmd = new PutObjectCommand({ Bucket: bucket, Key: key });
    uploadUrls[doc.fileName || key] = await getSignedUrl(s3, cmd, { expiresIn: 3600 });
  }

  await dynamo.send(new PutItemCommand({
    TableName: TABLE_CASE_STATE,
    Item: marshall({
      case_id: caseId,
      org_id: orgId,
      status: 'INTAKE_IN_PROGRESS',
      expected_upload_keys: JSON.stringify(expectedKeys),
      created_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }, { removeUndefinedValues: true }),
  }));

  const response = {
    caseId,
    policyVersion,
    requiredDocuments: docsToUpload,
    uploadUrls,
  };

  await setIdempotencyResponse(TABLE_IDEMPOTENCY, idempotencyKey, 200, JSON.stringify(response));
  log('INFO', 'Case initialized', addRequestContext({ caseId, orgId }, event));
  return { statusCode: 200, body: JSON.stringify(response) };
}

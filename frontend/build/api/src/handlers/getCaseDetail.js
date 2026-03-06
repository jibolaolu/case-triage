/**
 * GET /api/cases/{caseId} – case detail with AI analysis. Tenant: case must belong to caller org.
 * Includes presigned S3 URLs for document access.
 */
import { GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';
import { S3Client } from '@aws-sdk/client-s3';
import { getOrgIdFromEvent, validateOrgAccess, getUserIdFromEvent } from '../../shared/nodejs/tenant.js';
import { getPool } from '../../shared/nodejs/db.js';
import { logCaseAccessed } from '../../shared/nodejs/audit.js';

const s3 = new S3Client({});
const PRESIGN_EXPIRY = 3600;

export async function handler(event) {
  const caseId = event.pathParameters?.caseId;
  if (!caseId) return { statusCode: 400, body: JSON.stringify({ error: { code: 'MISSING_CASE_ID' } }) };

  const orgId = getOrgIdFromEvent(event);
  const userId = getUserIdFromEvent(event) || 'unknown';

  const pool = await getPool();
  const client = await pool.connect();
  try {
    const caseRow = await client.query(
      'SELECT case_id, organisation_id, case_type_id, status, policy_version, applicant_reference, created_at, updated_at, assigned_to FROM cases WHERE case_id = $1',
      [caseId]
    );
    if (!caseRow.rows.length) {
      return { statusCode: 404, body: JSON.stringify({ error: { code: 'NOT_FOUND', message: 'Case not found' } }) };
    }
    const c = caseRow.rows[0];
    validateOrgAccess(c.organisation_id, orgId);

    const [docRows, extractedRows, ruleRows] = await Promise.all([
      client.query('SELECT case_document_id, document_type, s3_object_path, s3_bucket, version FROM case_documents WHERE case_id = $1', [caseId]),
      client.query('SELECT field_name, value, confidence_score FROM extracted_case_data WHERE case_id = $1', [caseId]),
      client.query('SELECT rule_id, result, explanation FROM rule_evaluations WHERE case_id = $1', [caseId]),
    ]);

    await logCaseAccessed(client, caseId, userId, 'CASE_ACCESSED', { view: 'detail' });

    const documents = await Promise.all(
      docRows.rows.map(async (d) => {
        const url = await getSignedUrl(
          s3,
          new GetObjectCommand({ Bucket: d.s3_bucket, Key: d.s3_object_path }),
          { expiresIn: PRESIGN_EXPIRY }
        );
        return {
          documentId: d.case_document_id,
          documentType: d.document_type,
          s3Path: d.s3_object_path,
          bucket: d.s3_bucket,
          version: d.version,
          presignedUrl: url,
        };
      })
    );
    const extractedData = Object.fromEntries(extractedRows.rows.map(r => [r.field_name, r.value]));
    const ruleEvaluations = ruleRows.rows.map(r => ({ ruleId: r.rule_id, result: r.result, explanation: r.explanation }));

    const response = {
      caseId: c.case_id,
      organisationId: c.organisation_id,
      caseTypeId: c.case_type_id,
      status: c.status,
      policyVersion: c.policy_version,
      applicantReference: c.applicant_reference,
      createdAt: c.created_at,
      updatedAt: c.updated_at,
      assignedTo: c.assigned_to,
      documents,
      extractedData,
      ruleEvaluations,
      aiAnalysis: { extractedData, ruleEvaluations },
    };
    return { statusCode: 200, body: JSON.stringify(response) };
  } finally {
    client.release();
  }
}

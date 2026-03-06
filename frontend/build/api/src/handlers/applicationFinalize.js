/**
 * POST /applications/complete – validate documents, update state, emit CASE_INTAKE_VALIDATED.
 * Idempotency required. Tenant: validate case belongs to caller org.
 */
import { DynamoDBClient, GetItemCommand, UpdateItemCommand } from '@aws-sdk/client-dynamodb';
import { EventBridgeClient, PutEventsCommand } from '@aws-sdk/client-eventbridge';
import { HeadObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { marshall, unmarshall } from '@aws-sdk/util-dynamodb';
import { getOrgIdFromEvent, validateOrgAccess } from '../../shared/nodejs/tenant.js';
import { getIdempotencyResponse, setIdempotencyResponse, requireIdempotencyKey } from '../../shared/nodejs/idempotency.js';
import { log, addRequestContext } from '../../shared/nodejs/observability.js';
import { query } from '../../shared/nodejs/db.js';
import { putEvent } from '../../shared/nodejs/eventLog.js';
import { putIntakeFailures } from '../../shared/nodejs/emfMetrics.js';

const dynamo = new DynamoDBClient({});
const s3 = new S3Client({});
const eventBridge = new EventBridgeClient({});
const TABLE_IDEMPOTENCY = process.env.IDEMPOTENCY_TABLE;
const TABLE_CASE_STATE = process.env.CASE_STATE_TABLE;
const EVENT_BUS_NAME = process.env.EVENT_BUS_NAME || 'default';
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

  const { caseId } = body;
  if (!caseId) {
    putIntakeFailures(1);
    return { statusCode: 400, body: JSON.stringify({ error: { code: 'MISSING_CASE_ID', message: 'caseId is required' } }) };
  }

  const orgId = getOrgIdFromEvent(event);

  const caseRow = await query(
    'SELECT case_id, organisation_id, case_type_id, policy_id, policy_version, status FROM cases WHERE case_id = $1',
    [caseId]
  );
  if (!caseRow.rows.length) {
    putIntakeFailures(1);
    return { statusCode: 404, body: JSON.stringify({ error: { code: 'NOT_FOUND', message: 'Case not found' } }) };
  }
  const c = caseRow.rows[0];
  validateOrgAccess(c.organisation_id, orgId);

  if (c.status !== 'INTAKE_IN_PROGRESS') {
    putIntakeFailures(1);
    return { statusCode: 409, body: JSON.stringify({ error: { code: 'CONFLICT', message: `Case status is ${c.status}; expected INTAKE_IN_PROGRESS` } }) };
  }

  const stateItem = await dynamo.send(new GetItemCommand({
    TableName: TABLE_CASE_STATE,
    Key: marshall({ case_id: caseId }),
  }));
  const state = stateItem.Item ? unmarshall(stateItem.Item) : null;
  let expectedKeys = [];
  try {
    expectedKeys = state?.expected_upload_keys ? JSON.parse(state.expected_upload_keys) : [];
  } catch {
    expectedKeys = [];
  }

  const bucket = `${orgId}-${c.case_type_id}-applicant-intake-s3-${ENVIRONMENT}`;
  for (const { key, documentType, version } of expectedKeys) {
    try {
      await s3.send(new HeadObjectCommand({ Bucket: bucket, Key: key }));
    } catch (err) {
      putIntakeFailures(1);
      return {
        statusCode: 400,
        body: JSON.stringify({ error: { code: 'DOCUMENT_MISSING', message: `Document not found: ${key}` } }),
      };
    }
    const docId = `cd-${caseId}-${documentType}-${version}`;
    await query(
      `INSERT INTO case_documents (case_document_id, case_id, document_type, s3_object_path, s3_bucket, version)
       VALUES ($1, $2, $3, $4, $5, $6)
       ON CONFLICT (case_document_id) DO NOTHING`,
      [docId, caseId, documentType, key, bucket, version]
    );
  }

  await query(
    `UPDATE cases SET status = $1, intake_completed_at = NOW(), updated_at = NOW() WHERE case_id = $2`,
    ['INTAKE_VALIDATED', caseId]
  );

  await dynamo.send(new UpdateItemCommand({
    TableName: TABLE_CASE_STATE,
    Key: marshall({ case_id: caseId }),
    UpdateExpression: 'SET #status = :status, updated_at = :now REMOVE expected_upload_keys',
    ExpressionAttributeNames: { '#status': 'status' },
    ExpressionAttributeValues: marshall({
      ':status': 'INTAKE_VALIDATED',
      ':now': new Date().toISOString(),
    }),
  }));

  const detail = {
    schemaVersion: '1.0',
    caseId,
    orgId,
    caseType: c.case_type_id,
    policyVersion: c.policy_version,
    validatedAt: new Date().toISOString(),
    documentCount: expectedKeys.length,
  };

  await eventBridge.send(new PutEventsCommand({
    Entries: [{
      Source: 'case.intake',
      DetailType: 'CASE_INTAKE_VALIDATED',
      Detail: JSON.stringify(detail),
      Time: new Date(),
    }],
  }));

  await putEvent('CASE_INTAKE_VALIDATED', caseId, detail);
  log('INFO', 'CASE_INTAKE_VALIDATED emitted', addRequestContext({ caseId, orgId }, event));

  const response = {
    caseId,
    status: 'INTAKE_VALIDATED',
    documentsValidated: detail.documentCount,
    aiProcessingStarted: true,
  };
  await setIdempotencyResponse(TABLE_IDEMPOTENCY, idempotencyKey, 200, JSON.stringify(response));
  return { statusCode: 200, body: JSON.stringify(response) };
}

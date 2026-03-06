/**
 * POST /api/cases/{caseId}/decision – record human decision. Idempotency required. Tenant enforced.
 * Emits CASE_DECISION_RECORDED and persists to event_log.
 */
import { getOrgIdFromEvent, validateOrgAccess, getUserIdFromEvent } from '../../shared/nodejs/tenant.js';
import { getIdempotencyResponse, setIdempotencyResponse, requireIdempotencyKey } from '../../shared/nodejs/idempotency.js';
import { getClient } from '../../shared/nodejs/db.js';
import { logDecisionRecorded, logStatusChanged } from '../../shared/nodejs/audit.js';
import { putEvent } from '../../shared/nodejs/eventLog.js';
import { putDecisionLatency } from '../../shared/nodejs/emfMetrics.js';
import { EventBridgeClient, PutEventsCommand } from '@aws-sdk/client-eventbridge';

const TABLE_IDEMPOTENCY = process.env.IDEMPOTENCY_TABLE;
const EVENT_BUS_NAME = process.env.EVENT_BUS_NAME || 'default';
const eventBridge = new EventBridgeClient({});

const DECISION_TO_STATUS = {
  approve: 'APPROVED',
  decline: 'DECLINED',
  escalate: 'ESCALATED',
};

export async function handler(event) {
  const start = Date.now();
  const caseId = event.pathParameters?.caseId;
  if (!caseId) return { statusCode: 400, body: JSON.stringify({ error: { code: 'MISSING_CASE_ID' } }) };

  const idempotencyKey = requireIdempotencyKey(event.headers);
  const cached = await getIdempotencyResponse(TABLE_IDEMPOTENCY, idempotencyKey);
  if (cached) return { statusCode: cached.statusCode, body: cached.body };

  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return { statusCode: 400, body: JSON.stringify({ error: { code: 'INVALID_JSON' } }) };
  }

  const { decision, justification } = body;
  if (!decision || !justification || justification.length < 10) {
    return { statusCode: 400, body: JSON.stringify({ error: { code: 'VALIDATION_ERROR', message: 'decision and justification (min 10 chars) required' } }) };
  }
  const normDecision = decision.toLowerCase();
  if (!['approve', 'decline', 'escalate'].includes(normDecision)) {
    return { statusCode: 400, body: JSON.stringify({ error: { code: 'INVALID_DECISION', message: 'decision must be approve, decline, or escalate' } }) };
  }

  const orgId = getOrgIdFromEvent(event);
  const userId = getUserIdFromEvent(event) || 'unknown';
  const decisionId = `dec-${caseId}-${Date.now()}`;
  const newStatus = DECISION_TO_STATUS[normDecision];

  const client = await getClient();
  try {
    await client.query('BEGIN');

    const caseRow = await client.query(
      'SELECT case_id, organisation_id, status FROM cases WHERE case_id = $1 FOR UPDATE',
      [caseId]
    );
    if (!caseRow.rows.length) {
      await client.query('ROLLBACK');
      return { statusCode: 404, body: JSON.stringify({ error: { code: 'NOT_FOUND', message: 'Case not found' } }) };
    }
    const c = caseRow.rows[0];
    validateOrgAccess(c.organisation_id, orgId);

    await client.query(
      `INSERT INTO case_decisions (decision_id, case_id, decision, decided_by, justification, decided_at)
       VALUES ($1, $2, $3, $4, $5, NOW())`,
      [decisionId, caseId, newStatus, userId, justification]
    );

    await client.query(
      `UPDATE cases SET status = $1, decided_at = NOW(), updated_at = NOW() WHERE case_id = $2`,
      [newStatus, caseId]
    );

    await logDecisionRecorded(client, caseId, decisionId, newStatus, userId);
    await logStatusChanged(client, 'case', caseId, c.status, newStatus, userId, { decisionId });

    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }

  const decisionDetail = {
    schemaVersion: '1.0',
    caseId,
    orgId,
    decisionId,
    decision: newStatus,
    decidedBy: userId,
    decidedAt: new Date().toISOString(),
  };
  await eventBridge.send(new PutEventsCommand({
    Entries: [{
      Source: 'case.decision',
      DetailType: 'CASE_DECISION_RECORDED',
      Detail: JSON.stringify(decisionDetail),
    }],
  }));
  await putEvent('CASE_DECISION_RECORDED', caseId, decisionDetail);
  putDecisionLatency(Date.now() - start);

  const response = {
    caseId,
    decision: normDecision,
    decisionId,
    decidedAt: new Date().toISOString(),
    emailSent: false,
  };
  await setIdempotencyResponse(TABLE_IDEMPOTENCY, idempotencyKey, 200, JSON.stringify(response));
  return { statusCode: 200, body: JSON.stringify(response) };
}

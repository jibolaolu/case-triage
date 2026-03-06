/**
 * GET /applications/{caseId}/decision – return decision for upstream/citizen.
 * Tenant: authorise org access to case.
 */
import { getOrgIdFromEvent, validateOrgAccess } from '../../shared/nodejs/tenant.js';
import { query } from '../../shared/nodejs/db.js';

export async function handler(event) {
  const caseId = event.pathParameters?.caseId;
  if (!caseId) return { statusCode: 400, body: JSON.stringify({ error: { code: 'MISSING_CASE_ID' } }) };

  const orgId = getOrgIdFromEvent(event);

  const caseRow = await query('SELECT case_id, organisation_id, status, policy_version FROM cases WHERE case_id = $1', [caseId]);
  if (!caseRow.rows.length) {
    return { statusCode: 404, body: JSON.stringify({ error: { code: 'NOT_FOUND', message: 'Case not found' } }) };
  }
  const c = caseRow.rows[0];
  validateOrgAccess(c.organisation_id, orgId);

  const decRow = await query(
    'SELECT decision_id, decision, decided_by, justification, decided_at FROM case_decisions WHERE case_id = $1',
    [caseId]
  );

  if (!decRow.rows.length) {
    return {
      statusCode: 200,
      body: JSON.stringify({
        caseId,
        decision: 'PENDING',
        reason: '',
        confidence: null,
        policyVersion: c.policy_version,
        decidedAt: null,
      }),
    };
  }

  const d = decRow.rows[0];
  return {
    statusCode: 200,
    body: JSON.stringify({
      caseId,
      decision: d.decision,
      reason: d.justification,
      policyVersion: c.policy_version,
      decidedAt: d.decided_at,
    }),
  };
}

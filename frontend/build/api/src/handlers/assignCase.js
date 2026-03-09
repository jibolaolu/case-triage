/**
 * PUT /cases/{caseId}/assign – assign or reassign case to a caseworker.
 * Spec: assignedTo, assignedToName required.
 */
import { getOrgIdFromEvent, validateOrgAccess } from '../../shared/nodejs/tenant.js';
import { getClient } from '../../shared/nodejs/db.js';

export async function handler(event) {
  const caseId = event.pathParameters?.caseId;
  if (!caseId) {
    return { statusCode: 400, body: JSON.stringify({ error: 'caseId required' }) };
  }
  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON body' }) };
  }
  const { assignedTo, assignedToName } = body;
  if (!assignedTo || !assignedToName) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: 'assignedTo and assignedToName are required' }),
    };
  }

  const orgId = getOrgIdFromEvent(event);
  const client = await getClient();
  try {
    const caseRow = await client.query(
      'SELECT case_id, organisation_id FROM cases WHERE case_id = $1',
      [caseId]
    );
    if (!caseRow.rows.length) {
      return { statusCode: 404, body: JSON.stringify({ error: `Case ${caseId} not found` }) };
    }
    validateOrgAccess(caseRow.rows[0].organisation_id, orgId);
    await client.query(
      'UPDATE cases SET assigned_to = $1, updated_at = NOW() WHERE case_id = $2',
      [assignedTo, caseId]
    );
    return {
      statusCode: 200,
      body: JSON.stringify({ caseId, assignedTo, assignedToName }),
    };
  } finally {
    client.release();
  }
}

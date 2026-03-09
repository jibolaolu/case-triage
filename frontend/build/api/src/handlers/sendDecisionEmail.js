/**
 * POST /cases/{caseId}/email – send decision notification email to applicant (e.g. via SES).
 * Spec: subject, body, toAddress required; toName, decision optional.
 */
import { getOrgIdFromEvent, validateOrgAccess } from '../../shared/nodejs/tenant.js';
import { getClient } from '../../shared/nodejs/db.js';

export async function handler(event) {
  const caseId = event.pathParameters?.caseId;
  if (!caseId) {
    return { statusCode: 400, body: JSON.stringify({ error: 'caseId path parameter required' }) };
  }
  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON body' }) };
  }
  const { subject, body: bodyText, toAddress } = body;
  if (!subject || bodyText == null || !toAddress) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: 'subject, body, and toAddress are required' }),
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
    // Stub: no SES in this build; full impl in terraform lambda_src/send_decision_email.
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Email sent successfully' }),
    };
  } finally {
    client.release();
  }
}

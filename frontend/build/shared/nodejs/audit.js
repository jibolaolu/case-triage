/**
 * Audit logging to audit_logs table.
 * Supports: decision recorded, status changed, case accessed.
 * No PII in new_values; use IDs and action types only.
 * client: pg.Client from getClient() for use inside transactions.
 */

function auditId() {
  return `audit-${Date.now()}-${Math.random().toString(36).slice(2, 12)}`;
}

/**
 * Log when a decision is recorded for a case.
 */
export async function logDecisionRecorded(client, caseId, decisionId, decision, decidedBy, newValues = {}) {
  await client.query(
    `INSERT INTO audit_logs (audit_id, entity_type, entity_id, action, performed_by, performed_at, new_values)
     VALUES ($1, $2, $3, $4, $5, NOW(), $6::jsonb)`,
    [auditId(), 'case', caseId, 'DECISION_RECORDED', decidedBy, JSON.stringify({ decisionId, decision, ...newValues })]
  );
}

/**
 * Log when case status is changed.
 */
export async function logStatusChanged(client, entityType, entityId, oldStatus, newStatus, performedBy, newValues = {}) {
  await client.query(
    `INSERT INTO audit_logs (audit_id, entity_type, entity_id, action, performed_by, performed_at, new_values)
     VALUES ($1, $2, $3, $4, $5, NOW(), $6::jsonb)`,
    [auditId(), entityType, entityId, 'STATUS_CHANGED', performedBy, JSON.stringify({ oldStatus, newStatus, ...newValues })]
  );
}

/**
 * Log when a case is accessed (e.g. case detail or decision viewed).
 */
export async function logCaseAccessed(client, caseId, performedBy, action = 'CASE_ACCESSED', newValues = {}) {
  await client.query(
    `INSERT INTO audit_logs (audit_id, entity_type, entity_id, action, performed_by, performed_at, new_values)
     VALUES ($1, $2, $3, $4, $5, NOW(), $6::jsonb)`,
    [auditId(), 'case', caseId, action, performedBy, JSON.stringify(newValues)]
  );
}

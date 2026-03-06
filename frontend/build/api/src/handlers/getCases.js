/**
 * GET /api/cases – list cases for caseworker (filter by orgId from JWT).
 * Tenant: only cases for caller org returned.
 */
import { getOrgIdFromEvent } from '../../shared/nodejs/tenant.js';
import { query } from '../../shared/nodejs/db.js';

export async function handler(event) {
  const orgId = getOrgIdFromEvent(event);
  const status = event.queryStringParameters?.status || null;
  const page = Math.max(1, parseInt(event.queryStringParameters?.page, 10) || 1);
  const limit = Math.min(100, Math.max(1, parseInt(event.queryStringParameters?.limit, 10) || 20));
  const offset = (page - 1) * limit;

  const countResult = await query(
    `SELECT COUNT(*)::int AS total FROM cases WHERE organisation_id = $1 AND ($2::text IS NULL OR status = $2)`,
    [orgId, status]
  );
  const total = countResult.rows[0]?.total ?? 0;

  const casesResult = await query(
    `SELECT case_id AS "caseId", organisation_id AS "organisationId", case_type_id AS "caseTypeId", status, policy_version AS "policyVersion",
            created_at AS "createdAt", updated_at AS "updatedAt", assigned_to AS "assignedTo"
     FROM cases WHERE organisation_id = $1 AND ($2::text IS NULL OR status = $2)
     ORDER BY updated_at DESC LIMIT $3 OFFSET $4`,
    [orgId, status, limit, offset]
  );

  const cases = casesResult.rows;
  const response = {
    cases,
    pagination: {
      page,
      limit,
      total,
      totalPages: Math.ceil(total / limit) || 1,
    },
  };
  return { statusCode: 200, body: JSON.stringify(response) };
}

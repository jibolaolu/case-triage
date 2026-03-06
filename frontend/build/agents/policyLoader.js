/**
 * Load canonical policy from Aurora for agent runtime. Do not read from YAML/S3.
 */

import { query } from './db.js';

export async function loadPolicyByCaseId(caseId) {
  const caseRow = await query(
    'SELECT case_id, organisation_id, policy_id, policy_version FROM cases WHERE case_id = $1',
    [caseId]
  );
  if (!caseRow.rows.length) return null;
  const c = caseRow.rows[0];

  const [policyRow, docRows, ruleRows] = await Promise.all([
    query('SELECT policy_id, policy_definition, version FROM policies WHERE policy_id = $1', [c.policy_id]),
    query(
      'SELECT policy_document_id, document_type, mandatory, accepted_formats FROM policy_documents WHERE policy_id = $1',
      [c.policy_id]
    ),
    query(
      'SELECT rule_id, field_name, operator, comparison_value, description FROM policy_rules WHERE policy_id = $1',
      [c.policy_id]
    ),
  ]);

  if (!policyRow.rows.length) return null;
  return {
    caseId: c.case_id,
    organisationId: c.organisation_id,
    policyId: c.policy_id,
    policyVersion: c.policy_version,
    policyDefinition: policyRow.rows[0].policy_definition,
    requiredDocuments: docRows.rows,
    rules: ruleRows.rows,
  };
}

export async function loadCaseDocuments(caseId) {
  const r = await query(
    'SELECT case_document_id, case_id, document_type, s3_bucket, s3_object_path, version FROM case_documents WHERE case_id = $1',
    [caseId]
  );
  return r.rows;
}

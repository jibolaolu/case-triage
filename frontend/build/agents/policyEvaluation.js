/**
 * Agent 3: Policy evaluation. Load policy rules and extracted data from Aurora;
 * evaluate rules; persist to rule_evaluations and agent_executions; update DynamoDB POLICY_VALIDATED.
 */
import { DynamoDBClient, UpdateItemCommand } from '@aws-sdk/client-dynamodb';
import { marshall } from '@aws-sdk/util-dynamodb';
import { loadPolicyByCaseId } from './policyLoader.js';
import { query } from './db.js';

const dynamo = new DynamoDBClient({});
const TABLE = process.env.CASE_STATE_TABLE;

export async function handler(event) {
  const detail = event.detail ?? event;
  const caseId = detail.caseId;
  if (!caseId) throw new Error('Missing caseId');

  const startedAt = new Date().toISOString();
  const policy = await loadPolicyByCaseId(caseId);
  if (!policy) throw new Error('Case or policy not found: ' + caseId);

  const extractedRows = await query(
    'SELECT field_name, value FROM extracted_case_data WHERE case_id = $1',
    [caseId]
  );
  const extractedMap = Object.fromEntries(extractedRows.rows.map((r) => [r.field_name, r.value]));

  const ruleEvaluations = [];
  for (const rule of policy.rules || []) {
    const actual = extractedMap[rule.field_name];
    const actualVal = typeof actual === 'object' && actual !== null ? JSON.stringify(actual) : String(actual ?? '');
    const comp = rule.comparison_value;
    const compVal = typeof comp === 'object' && comp !== null && comp.value !== undefined ? comp.value : comp;
    const target = typeof compVal === 'number' ? compVal : String(compVal);
    let result = 'fail';

    const numActual = Number(actualVal);
    const numTarget = Number(target);
    if (!Number.isNaN(numActual) && !Number.isNaN(numTarget)) {
      switch (rule.operator) {
        case '<': result = numActual < numTarget ? 'pass' : 'fail'; break;
        case '<=': result = numActual <= numTarget ? 'pass' : 'fail'; break;
        case '>': result = numActual > numTarget ? 'pass' : 'fail'; break;
        case '>=': result = numActual >= numTarget ? 'pass' : 'fail'; break;
        case '=':
        case '==': result = numActual === numTarget ? 'pass' : 'fail'; break;
        default: result = actualVal === String(target) ? 'pass' : 'fail';
      }
    } else {
      result = actualVal === String(target) ? 'pass' : 'fail';
    }
    const explanation = (rule.description || rule.rule_id) + ': ' + result + ' (' + rule.field_name + ' ' + rule.operator + ' ' + target + ')';

    const evalId = 're-' + caseId + '-' + rule.rule_id + '-' + Date.now();
    await query(
      'INSERT INTO rule_evaluations (evaluation_id, case_id, rule_id, result, explanation, evaluated_at) VALUES ($1, $2, $3, $4, $5, NOW())',
      [evalId, caseId, rule.rule_id, result, explanation]
    );
    ruleEvaluations.push({ ruleId: rule.rule_id, result, explanation });
  }

  const passCount = ruleEvaluations.filter((r) => r.result === 'pass').length;
  const overallResult = passCount === ruleEvaluations.length ? 'ELIGIBLE' : ruleEvaluations.length > 0 ? 'CONDITIONAL' : 'INELIGIBLE';

  const completedAt = new Date().toISOString();
  const executionId = 'ae-policy-' + caseId + '-' + Date.now();
  await query(
    'INSERT INTO agent_executions (agent_execution_id, case_id, agent_name, status, started_at, completed_at, output) VALUES ($1, $2, $3, $4, $5::timestamptz, $6::timestamptz, $7::jsonb)',
    [executionId, caseId, 'policy_evaluation', 'success', startedAt, completedAt, JSON.stringify({ ruleEvaluations, overallResult })]
  );

  await dynamo.send(new UpdateItemCommand({
    TableName: TABLE,
    Key: marshall({ case_id: caseId }),
    UpdateExpression: 'SET #status = :status, updated_at = :now',
    ExpressionAttributeNames: { '#status': 'status' },
    ExpressionAttributeValues: marshall({
      ':status': 'POLICY_VALIDATED',
      ':now': completedAt,
    }),
  }));

  return {
    caseId,
    status: 'POLICY_VALIDATED',
    ruleEvaluations,
    overallResult,
    executedAt: completedAt,
  };
}

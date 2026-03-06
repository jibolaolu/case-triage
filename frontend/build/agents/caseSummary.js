/**
 * Agent 4: Case summary and recommendation. Load extracted data and rule evaluations from Aurora;
 * Bedrock for summary; persist to agent_executions. READY_FOR_CASEWORKER_REVIEW is set by updateCaseStatus step.
 */
import { loadPolicyByCaseId } from './policyLoader.js';
import { query } from './db.js';
import { BedrockRuntimeClient, InvokeModelCommand } from '@aws-sdk/client-bedrock-runtime';

const bedrock = new BedrockRuntimeClient({});
const MODEL_ID = process.env.BEDROCK_MODEL_ID || 'anthropic.claude-3-sonnet-20240229-v1:0';

export async function handler(event) {
  const detail = event.detail ?? event;
  const caseId = detail.caseId;
  if (!caseId) throw new Error('Missing caseId');

  const startedAt = new Date().toISOString();
  const policy = await loadPolicyByCaseId(caseId);
  if (!policy) throw new Error(`Case or policy not found: ${caseId}`);

  const [extractedRows, ruleRows] = await Promise.all([
    query('SELECT field_name, value, confidence_score FROM extracted_case_data WHERE case_id = $1', [caseId]),
    query('SELECT rule_id, result, explanation FROM rule_evaluations WHERE case_id = $1', [caseId]),
  ]);
  const extracted = Object.fromEntries(extractedRows.rows.map((r) => [r.field_name, r.value]));
  const rules = ruleRows.rows.map((r) => ({ ruleId: r.rule_id, result: r.result, explanation: r.explanation }));

  const summaryText = await generateSummaryWithBedrock(extracted, rules);
  const recommendation = rules.every((r) => r.result === 'pass') ? 'APPROVE' : 'REVIEW';
  const confidence = rules.length ? rules.filter((r) => r.result === 'pass').length / rules.length : 0.8;

  const completedAt = new Date().toISOString();
  const executionId = `ae-summary-${caseId}-${Date.now()}`;
  await query(
    `INSERT INTO agent_executions (agent_execution_id, case_id, agent_name, status, started_at, completed_at, output, model_version)
     VALUES ($1, $2, $3, $4, $5::timestamptz, $6::timestamptz, $7::jsonb, $8)`,
    [
      executionId,
      caseId,
      'case_summary',
      'success',
      startedAt,
      completedAt,
      JSON.stringify({
        summary: summaryText,
        recommendation,
        confidence,
        ruleSummary: rules.length,
      }),
      MODEL_ID,
    ]
  );

  return {
    caseId,
    status: 'READY_FOR_CASEWORKER_REVIEW',
    caseSummary: { summary: summaryText, recommendation, confidence },
    executedAt: completedAt,
  };
}

async function generateSummaryWithBedrock(extracted, rules) {
  try {
    const payload = {
      anthropic_version: 'bedrock-2023-05-31',
      max_tokens: 512,
      messages: [
        {
          role: 'user',
          content: `Summarise this case for a caseworker in 2-4 sentences. Extracted data: ${JSON.stringify(extracted)}. Rule results: ${JSON.stringify(rules)}. Be concise and factual.`,
        },
      ],
    };
    const res = await bedrock.send(
      new InvokeModelCommand({
        modelId: MODEL_ID,
        contentType: 'application/json',
        accept: 'application/json',
        body: JSON.stringify(payload),
      })
    );
    const body = JSON.parse(new TextDecoder().decode(res.body));
    return body.content?.[0]?.text?.trim() || 'Summary not generated.';
  } catch (err) {
    return `Summary generation failed: ${err.message}. Extracted fields: ${Object.keys(extracted).join(', ')}.`;
  }
}

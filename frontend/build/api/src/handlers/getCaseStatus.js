/**
 * GET /cases/{caseId}/status – case processing status (per-stage).
 * Spec: no auth. In this build, stub returns 501; full impl in Terraform Python Lambda (DynamoDB).
 */
export async function handler(event) {
  const caseId = event.pathParameters?.caseId;
  if (!caseId) {
    return { statusCode: 400, body: JSON.stringify({ error: 'caseId required' }) };
  }
  // Stub: full implementation lives in terraform/lambda_src/get_case_status (DynamoDB + stages).
  return {
    statusCode: 501,
    body: JSON.stringify({
      error: 'Not implemented in this build. Use deployed API (GET /cases/{caseId}/status).',
      caseId,
    }),
  };
}

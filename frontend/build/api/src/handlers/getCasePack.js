/**
 * GET /cases/{caseId}/pack – compiled case pack (AI summary, extracted data, rules).
 * Spec: no auth. In this build, stub returns 501; full impl in Terraform Python Lambda (S3).
 */
export async function handler(event) {
  const caseId = event.pathParameters?.caseId;
  if (!caseId) {
    return { statusCode: 400, body: JSON.stringify({ error: 'caseId path parameter required' }) };
  }
  // Stub: full implementation lives in terraform/lambda_src/get_case_pack (S3 case pack JSON).
  return {
    statusCode: 501,
    body: JSON.stringify({
      error: 'Case pack not found — pipeline may still be processing (stub). Use deployed API.',
      caseId,
    }),
  };
}

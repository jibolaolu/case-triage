/**
 * Admin policies: GET list, POST create, GET/{id}, PUT/{id}, DELETE/{id}.
 * Single Lambda in spec (case-triage-dev-manage-policy).
 */
export async function handler(event) {
  const method = event.requestContext?.http?.method ?? event.httpMethod ?? 'GET';
  const rawPath = event.rawPath ?? event.path ?? '';
  const policyId = event.pathParameters?.policyId;

  // GET /admin/policies – list
  if (method === 'GET' && rawPath === '/admin/policies') {
    const policies = [];
    return { statusCode: 200, body: JSON.stringify({ policies }) };
  }

  // POST /admin/policies – create
  if (method === 'POST' && rawPath === '/admin/policies') {
    let body;
    try {
      body = JSON.parse(event.body || '{}');
    } catch {
      return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON body' }) };
    }
    if (!body.orgId || !body.caseType) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: 'orgId and caseType are required' }),
      };
    }
    return {
      statusCode: 201,
      body: JSON.stringify({ message: 'Policy created', policyId: 'stub-policy-id' }),
    };
  }

  // GET /admin/policies/{policyId}
  if (method === 'GET' && policyId) {
    return {
      statusCode: 404,
      body: JSON.stringify({ error: 'Policy not found' }),
    };
  }

  // PUT /admin/policies/{policyId}
  if (method === 'PUT' && policyId) {
    let body;
    try {
      body = JSON.parse(event.body || '{}');
    } catch {
      return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON body' }) };
    }
    if (!body.status && body.effectiveDate == null && body.retiredDate == null) {
      return { statusCode: 400, body: JSON.stringify({ error: 'No fields to update' }) };
    }
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Policy updated successfully' }),
    };
  }

  // DELETE /admin/policies/{policyId}
  if (method === 'DELETE' && policyId) {
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Policy deleted successfully' }),
    };
  }

  return { statusCode: 404, body: JSON.stringify({ error: 'Not found' }) };
}

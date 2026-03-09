/**
 * Admin users: POST /admin/users (create), PUT .../role, PUT .../status, DELETE /admin/users/{userId}.
 * Dispatches by method and path; single Lambda in spec (case-triage-dev-manage-user).
 */
export async function handler(event) {
  const method = event.requestContext?.http?.method ?? event.httpMethod ?? 'GET';
  const rawPath = event.rawPath ?? event.path ?? '';
  const userId = event.pathParameters?.userId;

  // POST /admin/users – create user
  if (method === 'POST' && rawPath === '/admin/users') {
    let body;
    try {
      body = JSON.parse(event.body || '{}');
    } catch {
      return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON body' }) };
    }
    if (!body.email) {
      return { statusCode: 400, body: JSON.stringify({ error: 'email is required' }) };
    }
    // Stub: Cognito AdminCreateUser in Terraform manage_user.
    return {
      statusCode: 201,
      body: JSON.stringify({ message: 'User created successfully', email: body.email }),
    };
  }

  // PUT /admin/users/{userId}/role
  if (method === 'PUT' && userId && rawPath.endsWith('/role')) {
    let body;
    try {
      body = JSON.parse(event.body || '{}');
    } catch {
      return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON body' }) };
    }
    if (!body.role) {
      return { statusCode: 400, body: JSON.stringify({ error: 'role is required' }) };
    }
    const allowed = ['admin', 'caseworker', 'manager'];
    if (!allowed.includes(body.role)) {
      return {
        statusCode: 400,
        body: JSON.stringify({ error: `role must be one of: ${allowed.join(', ')}` }),
      };
    }
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Role updated successfully' }),
    };
  }

  // PUT /admin/users/{userId}/status
  if (method === 'PUT' && userId && rawPath.endsWith('/status')) {
    let body;
    try {
      body = JSON.parse(event.body || '{}');
    } catch {
      return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON body' }) };
    }
    if (typeof body.active !== 'boolean') {
      return { statusCode: 400, body: JSON.stringify({ error: 'active (boolean) is required' }) };
    }
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Status updated successfully' }),
    };
  }

  // DELETE /admin/users/{userId}
  if (method === 'DELETE' && userId) {
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'User deleted successfully' }),
    };
  }

  return { statusCode: 404, body: JSON.stringify({ error: 'Not found' }) };
}

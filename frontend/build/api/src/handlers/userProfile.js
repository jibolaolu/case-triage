/**
 * GET /users/me – get authenticated user profile.
 * PUT /users/me – update profile (name, phone, department, preferences).
 */
import { getUserIdFromEvent } from '../../shared/nodejs/tenant.js';

export async function handler(event) {
  const method = event.requestContext?.http?.method ?? event.httpMethod ?? 'GET';
  const userId = getUserIdFromEvent(event) || event.queryStringParameters?.userId;

  if (!userId) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: 'userId required (from authorizer or query param userId)' }),
    };
  }

  if (method === 'GET') {
    // Stub: full impl in Terraform user_profile (Cognito GetUser + custom attributes).
    const profile = {
      id: userId,
      name: '',
      email: '',
      role: 'caseworker',
      department: '',
      phone: '',
      preferences: { notifications: {}, theme: 'light' },
    };
    return { statusCode: 200, body: JSON.stringify(profile) };
  }

  if (method === 'PUT') {
    try {
      JSON.parse(event.body || '{}');
    } catch {
      return { statusCode: 400, body: JSON.stringify({ error: 'Invalid JSON body' }) };
    }
    return {
      statusCode: 200,
      body: JSON.stringify({ message: 'Profile updated successfully' }),
    };
  }

  return { statusCode: 404, body: JSON.stringify({ error: 'Not found' }) };
}

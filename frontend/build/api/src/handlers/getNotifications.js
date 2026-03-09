/**
 * GET /notifications – list notifications for the authenticated user.
 * Spec: query unreadOnly, userId (fallback).
 */
import { getUserIdFromEvent } from '../../shared/nodejs/tenant.js';

export async function handler(event) {
  const userId = getUserIdFromEvent(event) || event.queryStringParameters?.userId;
  if (!userId) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: 'userId required (from authorizer or query param userId)' }),
    };
  }
  const unreadOnly =
    event.queryStringParameters?.unreadOnly === 'true' ||
    event.queryStringParameters?.unreadOnly === '1' ||
    event.queryStringParameters?.unreadOnly === 'yes';
  // Stub: full impl in Terraform (DynamoDB notifications table). Return empty list.
  const notifications = [];
  return {
    statusCode: 200,
    body: JSON.stringify({ notifications }),
  };
}

/**
 * API Gateway router: dispatch by path and method. Tenant context and idempotency applied in handlers.
 * Production: use a proper router (e.g. find-my-way) or separate Lambda per resource.
 * MFA enforcement (P0) applied to all authenticated routes.
 */
import { log, addRequestContext } from '../shared/nodejs/observability.js';
import { checkMFAEnabled } from './middleware/mfaCheck.js';

export async function handler(event, context) {
  const requestId = event.requestContext?.requestId ?? context.awsRequestId;
  const path = event.rawPath ?? event.path ?? '';
  const method = event.requestContext?.http?.method ?? event.httpMethod ?? 'GET';

  log('INFO', 'Request', addRequestContext({ path, method }, event));

  // MFA Enforcement (P0) - Skip for public endpoints
  const publicPaths = ['/health', '/api/public'];
  const isPublicPath = publicPaths.some(p => path.startsWith(p));
  
  if (!isPublicPath && event.requestContext?.authorizer) {
    const mfaEnabled = await checkMFAEnabled(event);
    if (!mfaEnabled) {
      return {
        statusCode: 403,
        body: JSON.stringify({
          error: {
            code: 'MFA_REQUIRED',
            message: 'Multi-factor authentication (MFA) is required. Please enable MFA in your account settings.',
            requestId,
          },
        }),
      };
    }
  }

  try {
    if (path.startsWith('/applications/init') && method === 'POST') {
      return await import('./handlers/applicationInit.js').then(m => m.handler(event, context));
    }
    if (path.startsWith('/applications/complete') && method === 'POST') {
      return await import('./handlers/applicationFinalize.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/applications\/[^/]+\/decision$/) && method === 'GET') {
      return await import('./handlers/getDecision.js').then(m => m.handler(event, context));
    }
    if (path === '/api/cases' && method === 'GET') {
      return await import('./handlers/getCases.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/api\/cases\/[^/]+$/) && method === 'GET') {
      return await import('./handlers/getCaseDetail.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/api\/cases\/[^/]+\/decision$/) && method === 'POST') {
      return await import('./handlers/recordDecision.js').then(m => m.handler(event, context));
    }
    if (path === '/api/users/invite' && method === 'POST') {
      return await import('./handlers/inviteUser.js').then(m => m.handler(event, context));
    }

    return { statusCode: 404, body: JSON.stringify({ error: { code: 'NOT_FOUND', message: 'Route not found' } }) };
  } catch (err) {
    log('ERROR', err.message, addRequestContext({ stack: err.stack }, event));
    const statusCode = err.statusCode ?? 500;
    return {
      statusCode,
      body: JSON.stringify({
        error: {
          code: err.code ?? 'INTERNAL_ERROR',
          message: statusCode >= 500 ? 'Internal server error' : err.message,
          requestId,
        },
      }),
    };
  }
}

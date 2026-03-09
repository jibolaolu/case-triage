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
    // ─── Application intake (spec 1–3) ───────────────────────────────────────
    if (path.startsWith('/applications/init') && method === 'POST') {
      return await import('./handlers/applicationInit.js').then(m => m.handler(event, context));
    }
    if (path.startsWith('/applications/complete') && method === 'POST') {
      return await import('./handlers/applicationFinalize.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/applications\/[^/]+\/decision$/) && method === 'GET') {
      return await import('./handlers/getDecision.js').then(m => m.handler(event, context));
    }

    // ─── Cases: support both /cases and /api/cases for spec alignment ──────────
    const casesList = path === '/cases' || path === '/api/cases';
    const caseIdSegment = path.match(/^\/(?:api\/)?cases\/([^/]+)(?:\/(.*))?$/);
    const caseId = caseIdSegment?.[1];
    const caseSubPath = caseIdSegment?.[2] || '';

    if (casesList && method === 'GET') {
      return await import('./handlers/getCases.js').then(m => m.handler(event, context));
    }
    if (caseId && !caseSubPath && method === 'GET') {
      return await import('./handlers/getCaseDetail.js').then(m => m.handler(event, context));
    }
    if (caseId && caseSubPath === 'status' && method === 'GET') {
      return await import('./handlers/getCaseStatus.js').then(m => m.handler(event, context));
    }
    if (caseId && caseSubPath === 'pack' && method === 'GET') {
      return await import('./handlers/getCasePack.js').then(m => m.handler(event, context));
    }
    if (caseId && caseSubPath === 'decision' && method === 'POST') {
      return await import('./handlers/recordDecision.js').then(m => m.handler(event, context));
    }
    if (caseId && caseSubPath === 'assign' && method === 'PUT') {
      return await import('./handlers/assignCase.js').then(m => m.handler(event, context));
    }
    if (caseId && caseSubPath === 'email' && method === 'POST') {
      return await import('./handlers/sendDecisionEmail.js').then(m => m.handler(event, context));
    }

    // ─── Notifications (spec 4) ───────────────────────────────────────────────
    if (path === '/notifications' && method === 'GET') {
      return await import('./handlers/getNotifications.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/notifications\/[^/]+\/read$/) && method === 'PUT') {
      return await import('./handlers/markNotificationRead.js').then(m => m.handler(event, context));
    }

    // ─── Admin — Users (spec 5) ───────────────────────────────────────────────
    if (path === '/admin/users' && method === 'GET') {
      return await import('./handlers/listUsers.js').then(m => m.handler(event, context));
    }
    if (path === '/admin/users' && method === 'POST') {
      return await import('./handlers/manageUser.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/admin\/users\/[^/]+\/role$/) && method === 'PUT') {
      return await import('./handlers/manageUser.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/admin\/users\/[^/]+\/status$/) && method === 'PUT') {
      return await import('./handlers/manageUser.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/admin\/users\/[^/]+$/) && method === 'DELETE') {
      return await import('./handlers/manageUser.js').then(m => m.handler(event, context));
    }

    // ─── Admin — Policies (spec 6) ────────────────────────────────────────────
    if (path === '/admin/policies' && method === 'GET') {
      return await import('./handlers/managePolicy.js').then(m => m.handler(event, context));
    }
    if (path === '/admin/policies' && method === 'POST') {
      return await import('./handlers/managePolicy.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/admin\/policies\/[^/]+$/) && method === 'GET') {
      return await import('./handlers/managePolicy.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/admin\/policies\/[^/]+$/) && method === 'PUT') {
      return await import('./handlers/managePolicy.js').then(m => m.handler(event, context));
    }
    if (path.match(/^\/admin\/policies\/[^/]+$/) && method === 'DELETE') {
      return await import('./handlers/managePolicy.js').then(m => m.handler(event, context));
    }

    // ─── User profile (spec 7) ────────────────────────────────────────────────
    if (path === '/users/me' && method === 'GET') {
      return await import('./handlers/userProfile.js').then(m => m.handler(event, context));
    }
    if (path === '/users/me' && method === 'PUT') {
      return await import('./handlers/userProfile.js').then(m => m.handler(event, context));
    }

    // ─── Legacy build path (invite) ───────────────────────────────────────────
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

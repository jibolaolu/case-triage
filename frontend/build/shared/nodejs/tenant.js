/**
 * Multi-tenant isolation: extract and validate orgId from API Gateway event.
 * All tenant-scoped operations MUST use this before querying by organisation_id.
 */

export function getOrgIdFromEvent(event) {
  const claims = event?.requestContext?.authorizer?.claims || event?.requestContext?.authorizer?.jwt?.claims;
  const orgId = claims?.['custom:orgId'] ?? claims?.orgId;
  if (!orgId) throw new TenantContextError('Missing organisation context (orgId)');
  return orgId;
}

export function getUserIdFromEvent(event) {
  const claims = event?.requestContext?.authorizer?.claims || event?.requestContext?.authorizer?.jwt?.claims;
  return claims?.sub ?? claims?.userId ?? null;
}

export function validateOrgAccess(resourceOrgId, callerOrgId) {
  if (resourceOrgId !== callerOrgId) {
    throw new TenantContextError(`Access denied: resource org ${resourceOrgId} does not match caller org ${callerOrgId}`);
  }
}

export class TenantContextError extends Error {
  constructor(message) {
    super(message);
    this.name = 'TenantContextError';
    this.statusCode = 403;
  }
}

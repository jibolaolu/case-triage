/**
 * POST /api/users/invite – Create user in Cognito and Aurora (Admin only, P0).
 * Idempotency required. Multi-tenant: orgId from JWT and validated.
 */
import { CognitoIdentityProviderClient, AdminCreateUserCommand, AdminAddUserToGroupCommand } from '@aws-sdk/client-cognito-identity-provider';
import { getIdempotencyResponse, setIdempotencyResponse, requireIdempotencyKey } from '../../shared/nodejs/idempotency.js';
import { getOrgIdFromEvent, getUserIdFromEvent, validateOrgAccess } from '../../shared/nodejs/tenant.js';
import { query, getClient } from '../../shared/nodejs/db.js';
import { logStatusChanged } from '../../shared/nodejs/audit.js';
import { log, addRequestContext } from '../../shared/nodejs/observability.js';

const cognito = new CognitoIdentityProviderClient({});
const COGNITO_USER_POOL_ID = process.env.COGNITO_USER_POOL_ID;
const TABLE_IDEMPOTENCY = process.env.IDEMPOTENCY_TABLE;
const ENVIRONMENT = process.env.ENVIRONMENT || 'dev';

function generateInvitationId() {
  return `inv-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
}

function generateUserId(email) {
  return `usr-${email.split('@')[0]}-${Date.now().toString(36)}`;
}

export async function handler(event, context) {
  let body;
  try {
    body = JSON.parse(event.body || '{}');
  } catch {
    return { statusCode: 400, body: JSON.stringify({ error: { code: 'INVALID_JSON', message: 'Invalid JSON body' } }) };
  }

  const idempotencyKey = requireIdempotencyKey(event.headers);
  const cached = await getIdempotencyResponse(TABLE_IDEMPOTENCY, idempotencyKey);
  if (cached) return { statusCode: cached.statusCode, body: cached.body };

  const callerOrgId = getOrgIdFromEvent(event);
  const callerUserId = getUserIdFromEvent(event);

  // Validate admin role (check Cognito groups or user role in DB)
  const callerUser = await query('SELECT role FROM users WHERE user_id = $1 AND organisation_id = $2', [callerUserId, callerOrgId]);
  if (!callerUser.rows.length || !['Administrator', 'Admin'].includes(callerUser.rows[0].role)) {
    return { statusCode: 403, body: JSON.stringify({ error: { code: 'FORBIDDEN', message: 'Admin role required' } }) };
  }

  const { email, role, organisationId, firstName, lastName } = body;

  if (!email || !role || !organisationId) {
    return { statusCode: 400, body: JSON.stringify({ error: { code: 'MISSING_REQUIRED', message: 'email, role, and organisationId are required' } }) };
  }

  // Validate organisation access
  validateOrgAccess(organisationId, callerOrgId);

  // Validate organisation exists and is active
  const orgRow = await query('SELECT 1 FROM organisations WHERE organisation_id = $1 AND status = $2', [organisationId, 'active']);
  if (!orgRow.rows.length) {
    return { statusCode: 404, body: JSON.stringify({ error: { code: 'NOT_FOUND', message: 'Organisation not found or inactive' } }) };
  }

  // Validate role
  const validRoles = ['Caseworker', 'Manager', 'Administrator'];
  if (!validRoles.includes(role)) {
    return { statusCode: 400, body: JSON.stringify({ error: { code: 'INVALID_ROLE', message: `Role must be one of: ${validRoles.join(', ')}` } }) };
  }

  const client = await getClient();
  try {
    await client.query('BEGIN');

    // Check if user already exists
    const existingUser = await client.query('SELECT user_id FROM users WHERE email = $1 AND organisation_id = $2', [email, organisationId]);
    if (existingUser.rows.length) {
      await client.query('ROLLBACK');
      return { statusCode: 409, body: JSON.stringify({ error: { code: 'CONFLICT', message: 'User already exists' } }) };
    }

    // Create user in Cognito
    let cognitoUser;
    try {
      const createUserCmd = new AdminCreateUserCommand({
        UserPoolId: COGNITO_USER_POOL_ID,
        Username: email,
        UserAttributes: [
          { Name: 'email', Value: email },
          { Name: 'email_verified', Value: 'true' },
          ...(firstName ? [{ Name: 'given_name', Value: firstName }] : []),
          ...(lastName ? [{ Name: 'family_name', Value: lastName }] : []),
          { Name: 'custom:orgId', Value: organisationId },
        ],
        MessageAction: 'SUPPRESS', // Admin creates user; invitation email sent separately if needed
        TemporaryPassword: `TempPass${Math.random().toString(36).slice(2, 12)}!`, // User must change on first login
        DesiredDeliveryMediums: ['EMAIL'],
      });
      cognitoUser = await cognito.send(createUserCmd);
    } catch (err) {
      if (err.name === 'UsernameExistsException') {
        await client.query('ROLLBACK');
        return { statusCode: 409, body: JSON.stringify({ error: { code: 'CONFLICT', message: 'User already exists in Cognito' } }) };
      }
      throw err;
    }

    const userId = generateUserId(email);
    const cognitoSub = cognitoUser.User?.Username || email;

    // Add user to Cognito group (e.g., "council-a-Caseworkers")
    const groupName = `${organisationId}-${role}s`;
    try {
      await cognito.send(new AdminAddUserToGroupCommand({
        UserPoolId: COGNITO_USER_POOL_ID,
        Username: cognitoSub,
        GroupName: groupName,
      }));
    } catch (err) {
      // Group might not exist; log but don't fail
      log('WARN', `Failed to add user to group ${groupName}`, { error: err.message });
    }

    // Create invitation record
    const invitationId = generateInvitationId();
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7); // 7 days expiry

    await client.query(
      `INSERT INTO user_invitations (invitation_id, user_id, email, organisation_id, role, invited_at, expires_at, status)
       VALUES ($1, $2, $3, $4, $5, NOW(), $6, $7)`,
      [invitationId, userId, email, organisationId, role, expiresAt.toISOString(), 'PENDING']
    );

    // Create user record in Aurora
    await client.query(
      `INSERT INTO users (user_id, organisation_id, email, role, status, mfa_enabled, created_at, updated_at)
       VALUES ($1, $2, $3, $4, $5, $6, NOW(), NOW())`,
      [userId, organisationId, email, role, 'PENDING', false]
    );

    // Audit log
    await logStatusChanged(client, 'user', userId, null, 'PENDING', callerUserId, {
      invitationId,
      email,
      role,
      organisationId,
      action: 'USER_INVITED',
    });

    await client.query('COMMIT');

    const response = {
      userId,
      invitationId,
      email,
      role,
      organisationId,
      status: 'PENDING',
      cognitoUsername: cognitoSub,
      expiresAt: expiresAt.toISOString(),
    };

    await setIdempotencyResponse(TABLE_IDEMPOTENCY, idempotencyKey, 201, JSON.stringify(response));
    return { statusCode: 201, body: JSON.stringify(response) };
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    log('ERROR', err.message, addRequestContext({ stack: err.stack }, event));
    const statusCode = err.statusCode ?? 500;
    return {
      statusCode,
      body: JSON.stringify({
        error: {
          code: err.code ?? 'INTERNAL_ERROR',
          message: statusCode >= 500 ? 'Internal server error' : err.message,
          requestId: context.awsRequestId,
        },
      }),
    };
  } finally {
    client.release();
  }
}

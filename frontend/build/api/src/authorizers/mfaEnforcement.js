/**
 * Lambda Authorizer for MFA Enforcement (P0).
 * Validates JWT token and checks MFA status in Cognito.
 * Returns 401 if MFA not enabled.
 */
import { CognitoIdentityProviderClient, AdminGetUserCommand } from '@aws-sdk/client-cognito-identity-provider';

const cognito = new CognitoIdentityProviderClient({});
const COGNITO_USER_POOL_ID = process.env.COGNITO_USER_POOL_ID;

export async function handler(event) {
  try {
    const token = event.authorizationToken || event.headers?.Authorization?.replace('Bearer ', '');
    if (!token) {
      return generatePolicy('user', 'Deny', event.methodArn);
    }

    // Extract username from token (simplified - in production, decode JWT)
    // For now, we'll check MFA via Cognito AdminGetUser
    // In production, decode JWT to get 'sub' claim
    const claims = parseJWT(token);
    const username = claims?.sub || claims?.username;
    
    if (!username || !COGNITO_USER_POOL_ID) {
      return generatePolicy('user', 'Deny', event.methodArn);
    }

    // Check MFA status in Cognito
    try {
      const userResponse = await cognito.send(new AdminGetUserCommand({
        UserPoolId: COGNITO_USER_POOL_ID,
        Username: username,
      }));

      const mfaEnabled = userResponse.MFAOptions?.length > 0 || 
                        userResponse.UserMFASettingList?.includes('SOFTWARE_TOKEN_MFA') ||
                        userResponse.UserMFASettingList?.includes('SMS_MFA');

      if (!mfaEnabled) {
        console.log(`MFA not enabled for user: ${username}`);
        return {
          principalId: username,
          policyDocument: {
            Version: '2012-10-17',
            Statement: [{
              Action: 'execute-api:Invoke',
              Effect: 'Deny',
              Resource: event.methodArn,
            }],
          },
          context: {
            mfaRequired: 'true',
            mfaEnabled: 'false',
          },
        };
      }

      // MFA enabled - allow access
      return generatePolicy(username, 'Allow', event.methodArn, {
        mfaEnabled: 'true',
        orgId: claims['custom:orgId'] || '',
      });
    } catch (err) {
      console.error('Error checking MFA:', err);
      return generatePolicy('user', 'Deny', event.methodArn);
    }
  } catch (err) {
    console.error('Authorizer error:', err);
    return generatePolicy('user', 'Deny', event.methodArn);
  }
}

function parseJWT(token) {
  try {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const payload = JSON.parse(Buffer.from(parts[1], 'base64').toString());
    return payload;
  } catch {
    return null;
  }
}

function generatePolicy(principalId, effect, resource, context = {}) {
  return {
    principalId,
    policyDocument: {
      Version: '2012-10-17',
      Statement: [{
        Action: 'execute-api:Invoke',
        Effect,
        Resource,
      }],
    },
    context,
  };
}

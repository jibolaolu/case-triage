/**
 * MFA Enforcement Middleware (P0).
 * Checks MFA status from JWT claims or Cognito.
 * Returns 403 if MFA not enabled.
 */
import { CognitoIdentityProviderClient, AdminGetUserCommand } from '@aws-sdk/client-cognito-identity-provider';
import { getUserIdFromEvent } from '../../shared/nodejs/tenant.js';

const cognito = new CognitoIdentityProviderClient({});
const COGNITO_USER_POOL_ID = process.env.COGNITO_USER_POOL_ID;

/**
 * Check if user has MFA enabled.
 * In production, this should be checked via JWT claims or Cognito AdminGetUser.
 */
export async function checkMFAEnabled(event) {
  // Skip MFA check if Cognito not configured
  if (!COGNITO_USER_POOL_ID) {
    return true; // Allow in dev/test
  }

  try {
    const userId = getUserIdFromEvent(event);
    if (!userId) {
      return false;
    }

    // Check MFA status in Cognito
    const userResponse = await cognito.send(new AdminGetUserCommand({
      UserPoolId: COGNITO_USER_POOL_ID,
      Username: userId,
    }));

    const mfaEnabled = userResponse.MFAOptions?.length > 0 ||
                      userResponse.UserMFASettingList?.includes('SOFTWARE_TOKEN_MFA') ||
                      userResponse.UserMFASettingList?.includes('SMS_MFA');

    return mfaEnabled;
  } catch (err) {
    console.error('MFA check error:', err);
    // Fail closed - deny access if check fails
    return false;
  }
}

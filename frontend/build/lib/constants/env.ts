/**
 * Shared env key constants – align with Lambda and UI env vars.
 */

export const ENV_KEYS = {
  API_URL: 'NEXT_PUBLIC_API_URL',
  ENVIRONMENT: 'ENVIRONMENT',
  COGNITO_USER_POOL_ID: 'NEXT_PUBLIC_COGNITO_USER_POOL_ID',
  COGNITO_CLIENT_ID: 'NEXT_PUBLIC_COGNITO_CLIENT_ID',
} as const;

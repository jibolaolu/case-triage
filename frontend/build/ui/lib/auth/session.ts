import type { AuthUser } from '@/types';

const SESSION_KEY = 'faststart_user';

export type { AuthUser };

export function getCurrentUser(): AuthUser | null {
  if (typeof window === 'undefined') return null;
  try {
    const raw = localStorage.getItem(SESSION_KEY);
    if (!raw) return null;
    return JSON.parse(raw) as AuthUser;
  } catch {
    return null;
  }
}

export function setCurrentUser(user: AuthUser): void {
  if (typeof window === 'undefined') return;
  localStorage.setItem(SESSION_KEY, JSON.stringify(user));
}

export function getAccessToken(): string | null {
  if (typeof window === 'undefined') return null;
  try {
    // 1. Look for Cognito IdToken first (what API Gateway Cognito authorizer validates)
    const idTokenKey = Object.keys(localStorage).find(k =>
      k.includes('CognitoIdentityServiceProvider') && k.endsWith('.idToken')
    );
    if (idTokenKey) return localStorage.getItem(idTokenKey);

    // 2. Fallback: accessToken (some Amplify versions store it differently)
    const accessTokenKey = Object.keys(localStorage).find(k =>
      k.includes('CognitoIdentityServiceProvider') && k.endsWith('.accessToken')
    );
    if (accessTokenKey) return localStorage.getItem(accessTokenKey);

    // 3. Last resort: manually stored token
    return localStorage.getItem('faststart_access_token');
  } catch {
    return null;
  }
}

export function setAccessToken(token: string): void {
  if (typeof window === 'undefined') return;
  localStorage.setItem('faststart_access_token', token);
}

export async function signOut(): Promise<void> {
  if (typeof window !== 'undefined') {
    localStorage.removeItem(SESSION_KEY);
    localStorage.removeItem('faststart_access_token');
    window.location.href = '/login';
  }
}
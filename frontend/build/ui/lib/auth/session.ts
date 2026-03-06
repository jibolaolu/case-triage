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
    const cognitoKeys = Object.keys(localStorage).filter(k =>
      k.includes('CognitoIdentityServiceProvider') && k.endsWith('.accessToken')
    );
    if (cognitoKeys.length > 0) {
      return localStorage.getItem(cognitoKeys[0]);
    }
    const token = localStorage.getItem('faststart_access_token');
    return token;
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
    window.location.href = '/login';
  }
}

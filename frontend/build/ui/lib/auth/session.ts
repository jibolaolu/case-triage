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
    const keys = Object.keys(localStorage);

    // 1. Amplify v5 / Cognito hosted UI — idToken (used by API Gateway Cognito authorizer)
    const idTokenKey = keys.find(k =>
      k.includes('CognitoIdentityServiceProvider') && k.endsWith('.idToken')
    );
    if (idTokenKey) {
      const token = localStorage.getItem(idTokenKey);
      if (token) return token;
    }

    // 2. Amplify v6 — stores tokens under a different key pattern
    const ampV6IdToken = keys.find(k =>
      k.includes('amplify') && k.toLowerCase().includes('idtoken')
    );
    if (ampV6IdToken) {
      const raw = localStorage.getItem(ampV6IdToken);
      if (raw) {
        try {
          // Amplify v6 may store as JSON object with a 'value' field
          const parsed = JSON.parse(raw);
          if (parsed?.value) return parsed.value;
          if (typeof parsed === 'string') return parsed;
        } catch {
          return raw; // plain string token
        }
      }
    }

    // 3. Amplify v5 accessToken fallback
    const accessTokenKey = keys.find(k =>
      k.includes('CognitoIdentityServiceProvider') && k.endsWith('.accessToken')
    );
    if (accessTokenKey) {
      const token = localStorage.getItem(accessTokenKey);
      if (token) return token;
    }

    // 4. Amplify v6 accessToken fallback
    const ampV6AccessToken = keys.find(k =>
      k.includes('amplify') && k.toLowerCase().includes('accesstoken')
    );
    if (ampV6AccessToken) {
      const raw = localStorage.getItem(ampV6AccessToken);
      if (raw) {
        try {
          const parsed = JSON.parse(raw);
          if (parsed?.value) return parsed.value;
          if (typeof parsed === 'string') return parsed;
        } catch {
          return raw;
        }
      }
    }

    // 5. Last resort: manually stored token
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

'use client';

import { useRouter } from 'next/navigation';
import { useState } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { setAccessToken } from '@/lib/auth/session';
import type { AuthUser } from '@/types';

const DEMO_USERS: AuthUser[] = [
  { id: 'u3', name: 'Sarah Johnson',  email: 'sarah.johnson@agency.gov',  role: 'CASEWORKER' },
  { id: 'u4', name: 'James Patel',    email: 'james.patel@agency.gov',    role: 'CASEWORKER' },
  { id: 'u6', name: 'Michael Chen',   email: 'michael.chen@agency.gov',   role: 'MANAGER'    },
  { id: 'u7', name: 'Priya Nair',     email: 'priya.nair@agency.gov',     role: 'MANAGER'    },
  { id: 'u1', name: 'David Williams', email: 'david.williams@agency.gov', role: 'ADMIN'      },
  { id: 'u2', name: 'Emma Thompson',  email: 'emma.thompson@agency.gov',  role: 'ADMIN'      },
];

const roleColors: Record<string, string> = {
  CASEWORKER: 'bg-fast-caseworker',
  MANAGER:    'bg-fast-manager',
  ADMIN:      'bg-fast-admin',
};

const roleLabels: Record<string, string> = {
  CASEWORKER: 'Caseworker',
  MANAGER:    'Manager',
  ADMIN:      'Admin',
};

export default function LoginPage() {
  const { login } = useAuth();
  const router = useRouter();

  // Cognito login form state
  const [username, setUsername]   = useState('');
  const [password, setPassword]   = useState('');
  const [error, setError]         = useState('');
  const [loading, setLoading]     = useState(false);
  const [showCognito, setShowCognito] = useState(false);

  // Demo login — no token, mock data only
  const handleDemoLogin = (user: AuthUser) => {
    login(user);
    router.push('/dashboard');
  };

  // Real Cognito login — fetches IdToken and stores it
  const handleCognitoLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setError('');
    setLoading(true);

    try {
      const clientId = process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID;
      if (!clientId) throw new Error('NEXT_PUBLIC_COGNITO_CLIENT_ID is not set');

      const resp = await fetch(
        `https://cognito-idp.eu-west-2.amazonaws.com/`,
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-amz-json-1.1',
            'X-Amz-Target': 'AWSCognitoIdentityProviderService.InitiateAuth',
          },
          body: JSON.stringify({
            AuthFlow: 'USER_PASSWORD_AUTH',
            ClientId: clientId,
            AuthParameters: {
              USERNAME: username,
              PASSWORD: password,
            },
          }),
        }
      );

      const data = await resp.json();

      if (!resp.ok) {
        throw new Error(data.message || data.__type || 'Authentication failed');
      }

      const idToken     = data.AuthenticationResult?.IdToken;
      const accessToken = data.AuthenticationResult?.AccessToken;

      if (!idToken) throw new Error('No token returned from Cognito');

      // Store token so getAccessToken() in session.ts can find it
      setAccessToken(idToken);
      // Also store access token as backup
      if (accessToken) {
        localStorage.setItem('faststart_access_token_access', accessToken);
      }

      // Build user from Cognito — parse name/role from token claims if available
      // or use a sensible default that the portal can work with
      const payload = JSON.parse(atob(idToken.split('.')[1]));
      const cognitoUser: AuthUser = {
        id:    payload.sub,
        name:  payload.name ?? payload['cognito:username'] ?? username,
        email: payload.email ?? username,
        role:  (payload['custom:role'] ?? 'CASEWORKER') as AuthUser['role'],
      };

      login(cognitoUser);
      router.push('/dashboard');

    } catch (err) {
      setError(err instanceof Error ? err.message : 'Login failed');
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="min-h-screen bg-fast-bg flex flex-col">
      {/* Header */}
      <header className="bg-fast-sidebar text-white p-4">
        <div className="max-w-7xl mx-auto flex items-center gap-3">
          <img
            src="/version1-logo.svg"
            alt="Version 1"
            className="h-10 w-auto object-contain"
          />
          <div>
            <p className="text-xs font-semibold tracking-widest uppercase text-fast-cyan">VERSION 1</p>
            <h1 className="text-lg font-bold">FastStartAI</h1>
            <p className="text-xs text-white/80">AI-Powered Case Review System</p>
          </div>
        </div>
      </header>

      <main className="flex-1 flex items-center justify-center p-8">
        <div className="max-w-md w-full space-y-6">

          {/* Cognito SSO Card */}
          <div className="bg-fast-panel rounded-lg shadow-card p-8">
            <h2 className="text-xl font-bold text-fast-text mb-4 text-center">Sign In</h2>

            {!showCognito ? (
              <>
                <div className="bg-fast-teal-light border border-fast-teal/30 rounded-lg p-3 mb-4">
                  <p className="text-sm text-fast-teal">
                    <strong>Note:</strong> Sign in with your Cognito credentials to load live cases
                    from the API. Use Demo Login below for mock data only.
                  </p>
                </div>
                <button
                  onClick={() => setShowCognito(true)}
                  className="w-full flex items-center justify-center gap-2 px-6 py-3 bg-fast-teal text-white rounded-md font-semibold hover:opacity-90 transition-colors"
                >
                  <span>🛡️</span>
                  Sign In with Cognito
                </button>
              </>
            ) : (
              <form onSubmit={handleCognitoLogin} className="space-y-4">
                <div>
                  <label className="block text-sm font-medium text-fast-text mb-1">
                    Username / Email
                  </label>
                  <input
                    type="text"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    required
                    className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal"
                    placeholder="testuser"
                  />
                </div>
                <div>
                  <label className="block text-sm font-medium text-fast-text mb-1">
                    Password
                  </label>
                  <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    required
                    className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal"
                    placeholder="••••••••"
                  />
                </div>
                {error && (
                  <p className="text-sm text-fast-declined bg-fast-red-light px-3 py-2 rounded-md">
                    {error}
                  </p>
                )}
                <button
                  type="submit"
                  disabled={loading}
                  className="w-full px-6 py-3 bg-fast-teal text-white rounded-md font-semibold hover:opacity-90 transition-colors disabled:opacity-50"
                >
                  {loading ? 'Signing in…' : 'Sign In'}
                </button>
                <button
                  type="button"
                  onClick={() => { setShowCognito(false); setError(''); }}
                  className="w-full text-sm text-fast-muted hover:text-fast-text transition-colors"
                >
                  ← Back
                </button>
              </form>
            )}
          </div>

          {/* Demo user selection */}
          <div className="bg-fast-panel rounded-lg shadow-card p-6">
            <h3 className="text-base font-semibold text-fast-text mb-1">
              Demo – Select a user to simulate login
            </h3>
            <p className="text-xs text-fast-muted mb-4">
              Uses mock data only. Sign in with Cognito above to load real cases from the API.
            </p>
            <div className="space-y-2">
              {DEMO_USERS.map((user) => (
                <button
                  key={user.id}
                  onClick={() => handleDemoLogin(user)}
                  className="w-full flex items-center justify-between p-3 bg-gray-50 hover:bg-gray-100 rounded-lg transition-colors text-left"
                >
                  <div className="flex items-center gap-3">
                    <div
                      className={`w-10 h-10 ${roleColors[user.role]} rounded-full flex items-center justify-center text-white font-semibold text-sm`}
                    >
                      {user.name.split(' ').map((n) => n[0]).join('')}
                    </div>
                    <div>
                      <p className="font-medium text-fast-text text-sm">{user.name}</p>
                      <p className="text-xs text-fast-muted">{user.email}</p>
                    </div>
                  </div>
                  <span
                    className={`px-3 py-1 text-xs font-semibold text-white rounded-full ${roleColors[user.role]}`}
                  >
                    {roleLabels[user.role]}
                  </span>
                </button>
              ))}
            </div>
          </div>

          <div className="text-center text-sm text-fast-muted">
            <p>Privacy Policy | Terms of Service | Support</p>
            <p className="mt-1">support@faststart.ai | (555) 123-4567</p>
          </div>
        </div>
      </main>
    </div>
  );
}
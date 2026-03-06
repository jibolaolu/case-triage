'use client';

import { useRouter } from 'next/navigation';
import { useAuth } from '@/contexts/AuthContext';
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

  const handleLogin = (user: AuthUser) => {
    login(user);
    router.push('/dashboard');
  };

  return (
    <div className="min-h-screen bg-fast-bg flex flex-col">
      {/* Header (requirements 6.2 Logo; specification Layout Logo) */}
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
          {/* SSO Card */}
          <div className="bg-fast-panel rounded-lg shadow-card p-8">
            <h2 className="text-xl font-bold text-fast-text mb-4 text-center">Sign In</h2>
            <div className="bg-fast-teal-light border border-fast-teal/30 rounded-lg p-3 mb-4">
              <p className="text-sm text-fast-teal">
                <strong>Note:</strong> This system uses secure SSO authentication. In production, you
                will be redirected to your organisation&apos;s login page.
              </p>
            </div>
            <button
              onClick={() => handleLogin(DEMO_USERS[0])}
              className="w-full flex items-center justify-center gap-2 px-6 py-3 bg-fast-teal text-white rounded-md font-semibold hover:opacity-90 transition-colors"
            >
              <span>🛡️</span>
              Sign In with Single Sign-On
            </button>
          </div>

          {/* Demo user selection */}
          <div className="bg-fast-panel rounded-lg shadow-card p-6">
            <h3 className="text-base font-semibold text-fast-text mb-1">Demo – Select a user to simulate login</h3>
            <p className="text-xs text-fast-muted mb-4">
              Each role has different screen access. Admin cannot access Case Management or Escalated Cases.
            </p>
            <div className="space-y-2">
              {DEMO_USERS.map((user) => (
                <button
                  key={user.id}
                  onClick={() => handleLogin(user)}
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

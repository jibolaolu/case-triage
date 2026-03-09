'use client';

import { useState, useEffect } from 'react';
import { useAuth } from '@/contexts/AuthContext';
import { useUserProfile, useUpdateUserProfile } from '@/hooks/useUserProfile';

const roleLabel: Record<string, string> = {
  ADMIN: 'Admin',
  CASEWORKER: 'Caseworker',
  MANAGER: 'Manager',
};

export default function SettingsPage() {
  const { user } = useAuth();
  const { data: profile, isLoading: profileLoading } = useUserProfile();
  const updateProfileMutation = useUpdateUserProfile();

  const [profileOpen, setProfileOpen] = useState(true);
  const [notifOpen, setNotifOpen] = useState(false);
  const [displayOpen, setDisplayOpen] = useState(false);

  const nameFromProfile = profile?.name ?? user?.name ?? '';
  const nameParts = nameFromProfile.split(' ');
  const firstName = nameParts[0] ?? '';
  const lastName = nameParts.slice(1).join(' ') || '';

  const [first, setFirst] = useState(firstName);
  const [last, setLast] = useState(lastName);
  const [phone, setPhone] = useState(profile?.phone ?? '(555) 234-5678');
  const [department, setDepartment] = useState(profile?.department ?? 'General Services');

  useEffect(() => {
    if (profile) {
      const parts = (profile.name ?? '').split(' ');
      setFirst(parts[0] ?? '');
      setLast(parts.slice(1).join(' ') || '');
      if (profile.phone) setPhone(profile.phone);
      if (profile.department) setDepartment(profile.department);
    } else if (user?.name) {
      const parts = user.name.split(' ');
      setFirst(parts[0] ?? '');
      setLast(parts.slice(1).join(' ') || '');
    }
  }, [profile, user?.name]);

  const initials = (nameFromProfile || user?.name ?? '')
    .split(' ')
    .map((n) => n[0])
    .join('')
    .toUpperCase()
    .slice(0, 2);

  const handleSaveProfile = () => {
    updateProfileMutation.mutate({
      name: [first.trim(), last.trim()].filter(Boolean).join(' '),
      phone: phone.trim() || undefined,
      department: department.trim() || undefined,
      preferences: profile?.preferences,
    });
  };

  if (profileLoading && !profile) {
    return (
      <div className="p-6">
        <div className="flex items-center justify-center py-12 text-fast-muted text-sm">Loading profile…</div>
      </div>
    );
  }

  return (
    <div className="p-6 flex flex-col lg:flex-row gap-6">
      {/* Main content */}
      <div className="flex-1 min-w-0">
        <div className="mb-6">
          <div className="flex items-center gap-2 mb-1">
            <span className="text-2xl">⚙️</span>
            <h1 className="text-3xl font-bold text-fast-teal">Settings</h1>
          </div>
          <p className="text-base text-fast-muted">Manage your account and application preferences</p>
        </div>

        {/* Profile Information */}
        <section className="bg-fast-panel rounded-lg shadow-card overflow-hidden mb-4">
          <button
            type="button"
            onClick={() => setProfileOpen((o) => !o)}
            className="w-full px-5 py-4 flex items-center justify-between text-left"
          >
            <h2 className="text-lg font-semibold text-fast-text">Profile Information</h2>
            <span className="text-fast-muted">{profileOpen ? '▼' : '▶'}</span>
          </button>
          {profileOpen && (
            <div className="px-5 pb-5 pt-0 border-t border-gray-100">
              <div className="flex flex-wrap items-start gap-6 mb-6">
                <div className="flex flex-col items-center gap-2">
                  <div className="w-20 h-20 rounded-full bg-fast-teal flex items-center justify-center text-2xl font-bold text-white">
                    {initials}
                  </div>
                  <button
                    type="button"
                    className="text-sm text-fast-teal font-medium hover:underline"
                  >
                    Change Photo
                  </button>
                  <p className="text-xs text-fast-muted">JPG, PNG or GIF. Max 2MB</p>
                </div>
                <div className="flex-1 grid grid-cols-1 sm:grid-cols-2 gap-4 min-w-[200px]">
                  <div>
                    <label className="block text-sm font-medium text-fast-text mb-1">First Name</label>
                    <input
                      type="text"
                      value={first}
                      onChange={(e) => setFirst(e.target.value)}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-fast-text mb-1">Last Name</label>
                    <input
                      type="text"
                      value={last}
                      onChange={(e) => setLast(e.target.value)}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal"
                    />
                  </div>
                  <div className="sm:col-span-2">
                    <label className="block text-sm font-medium text-fast-text mb-1">Email</label>
                    <input
                      type="email"
                      readOnly
                      value={user?.email ?? ''}
                      className="w-full px-3 py-2 border border-gray-200 rounded-md text-sm bg-gray-50 text-fast-muted"
                    />
                    <p className="text-xs text-fast-muted mt-1">Email cannot be changed. Contact IT for assistance.</p>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-fast-text mb-1">Phone</label>
                    <input
                      type="tel"
                      value={phone}
                      onChange={(e) => setPhone(e.target.value)}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal"
                    />
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-fast-text mb-1">Role</label>
                    <p className="py-2 text-sm font-medium text-fast-approved">
                      {user?.role ? roleLabel[user.role] ?? user.role : '—'}
                    </p>
                  </div>
                  <div>
                    <label className="block text-sm font-medium text-fast-text mb-1">Department</label>
                    <input
                      type="text"
                      value={department}
                      onChange={(e) => setDepartment(e.target.value)}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal"
                    />
                  </div>
                </div>
              </div>
              {updateProfileMutation.isSuccess && (
                <p className="text-sm text-fast-approved mb-2">Profile updated successfully.</p>
              )}
              {updateProfileMutation.isError && (
                <p className="text-sm text-fast-declined mb-2">
                  {updateProfileMutation.error instanceof Error ? updateProfileMutation.error.message : 'Failed to update profile'}
                </p>
              )}
              <button
                type="button"
                onClick={handleSaveProfile}
                disabled={updateProfileMutation.isPending}
                className="px-4 py-2 bg-fast-approved text-white rounded-md font-medium hover:bg-fast-teal transition-colors disabled:opacity-50"
              >
                {updateProfileMutation.isPending ? 'Saving…' : 'Save Changes'}
              </button>
            </div>
          )}
        </section>

        {/* Notifications */}
        <section className="bg-fast-panel rounded-lg shadow-card overflow-hidden mb-4">
          <button
            type="button"
            onClick={() => setNotifOpen((o) => !o)}
            className="w-full px-5 py-4 flex items-center justify-between text-left"
          >
            <h2 className="text-lg font-semibold text-fast-text">Notifications</h2>
            <span className="text-fast-muted">{notifOpen ? '▼' : '▶'}</span>
          </button>
          {notifOpen && (
            <div className="px-5 pb-5 pt-0 border-t border-gray-100 space-y-3">
              <label className="flex items-center gap-3">
                <input type="checkbox" className="rounded border-gray-300 text-fast-teal focus:ring-fast-teal" defaultChecked />
                <span className="text-sm text-fast-text">Case assigned</span>
              </label>
              <label className="flex items-center gap-3">
                <input type="checkbox" className="rounded border-gray-300 text-fast-teal focus:ring-fast-teal" defaultChecked />
                <span className="text-sm text-fast-text">Case ready for review</span>
              </label>
              <label className="flex items-center gap-3">
                <input type="checkbox" className="rounded border-gray-300 text-fast-teal focus:ring-fast-teal" />
                <span className="text-sm text-fast-text">Deadline approaching</span>
              </label>
              <label className="flex items-center gap-3">
                <input type="checkbox" className="rounded border-gray-300 text-fast-teal focus:ring-fast-teal" />
                <span className="text-sm text-fast-text">System updates</span>
              </label>
            </div>
          )}
        </section>

        {/* Display Preferences */}
        <section className="bg-fast-panel rounded-lg shadow-card overflow-hidden">
          <button
            type="button"
            onClick={() => setDisplayOpen((o) => !o)}
            className="w-full px-5 py-4 flex items-center justify-between text-left"
          >
            <h2 className="text-lg font-semibold text-fast-text">Display Preferences</h2>
            <span className="text-fast-muted">{displayOpen ? '▼' : '▶'}</span>
          </button>
          {displayOpen && (
            <div className="px-5 pb-5 pt-0 border-t border-gray-100 space-y-3">
              <label className="flex items-center gap-3">
                <input type="radio" name="theme" className="text-fast-teal focus:ring-fast-teal" defaultChecked />
                <span className="text-sm text-fast-text">Light theme</span>
              </label>
              <label className="flex items-center gap-3">
                <input type="radio" name="theme" className="text-fast-teal focus:ring-fast-teal" />
                <span className="text-sm text-fast-text">Dark theme</span>
              </label>
            </div>
          )}
        </section>
      </div>

      {/* Right sidebar — Help & Support, System Information */}
      <aside className="w-full lg:w-80 flex-shrink-0">
        <div className="bg-fast-panel rounded-lg shadow-card p-5 mb-4">
          <h3 className="text-base font-semibold text-fast-text mb-4">Help & Support</h3>
          <div className="space-y-3 text-sm">
            <div>
              <p className="font-medium text-fast-muted mb-0.5">Contact Support</p>
              <p className="text-fast-text">support@housingagency.gov</p>
              <p className="text-fast-text">(555) 123-4567</p>
            </div>
            <div>
              <p className="font-medium text-fast-muted mb-2">Quick Links</p>
              <ul className="space-y-1.5">
                <li><a href="#" className="text-fast-teal hover:underline">User Guide</a></li>
                <li><a href="#" className="text-fast-teal hover:underline">FAQ</a></li>
                <li><a href="#" className="text-fast-teal hover:underline">Video Tutorials</a></li>
                <li><a href="#" className="text-fast-teal hover:underline">System Status</a></li>
                <li><a href="#" className="text-fast-teal hover:underline">AI Guide</a></li>
              </ul>
            </div>
          </div>
        </div>
        <div className="bg-fast-panel rounded-lg shadow-card p-5">
          <h3 className="text-base font-semibold text-fast-text mb-4">System Information</h3>
          <div className="space-y-2 text-sm">
            <p className="text-fast-muted">Version: <span className="text-fast-text">1.0.0</span></p>
            <p className="text-fast-muted">Last Updated: <span className="text-fast-text">Feb 10, 2026</span></p>
            <p className="text-fast-muted">Status: <span className="inline-block px-2 py-0.5 bg-fast-teal-light text-fast-teal rounded-full font-medium">Operational</span></p>
          </div>
        </div>
      </aside>
    </div>
  );
}

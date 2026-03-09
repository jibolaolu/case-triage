'use client';

import Link from 'next/link';
import { usePathname, useRouter } from 'next/navigation';
import { useEffect } from 'react';
import { cn } from '@/lib/utils';
import { useAuth } from '@/contexts/AuthContext';
import { useNotifications } from '@/hooks/useNotifications';
import { getNotificationsForRole } from '@/data/mockData';

type NavItem = {
  href: string;
  label: string;
  icon: string;
  badge?: number;
};

const caseworkerNav: NavItem[] = [
  { href: '/dashboard',   label: 'Dashboard',       icon: '📊' },
  { href: '/cases',       label: 'Case Management', icon: '📁' },
  { href: '/notifications', label: 'Notifications', icon: '🔔' },
  { href: '/settings',    label: 'Settings',        icon: '⚙️' },
];

const managerNav: NavItem[] = [
  { href: '/dashboard',   label: 'Dashboard',       icon: '📊' },
  { href: '/cases',       label: 'Case Management', icon: '📁' },
  { href: '/escalated',   label: 'Escalated Cases', icon: '⚠️' },
  { href: '/notifications', label: 'Notifications', icon: '🔔' },
  { href: '/settings',    label: 'Settings',        icon: '⚙️' },
];

const adminNav: NavItem[] = [
  { href: '/dashboard',    label: 'Dashboard',       icon: '📊' },
  { href: '/admin/users',  label: 'User Management', icon: '👥' },
  { href: '/admin/policies', label: 'Policy Management', icon: '📋' },
  { href: '/notifications', label: 'Notifications',  icon: '🔔' },
  { href: '/settings',    label: 'Settings',        icon: '⚙️' },
];

// Routes that Admin must not access
const ADMIN_RESTRICTED = ['/cases', '/escalated', '/email-review'];
// Routes that Caseworker/Manager must not access
const CASEWORKER_RESTRICTED = ['/admin'];
// Escalated cases: Managers only (Caseworker must not access)
const ESCALATED_ONLY_MANAGER = '/escalated';

export default function DashboardLayout({ children }: { children: React.ReactNode }) {
  const pathname = usePathname();
  const router = useRouter();
  const { user, loading, logout } = useAuth();

  // Redirect to login if not authenticated
  useEffect(() => {
    if (!loading && !user) {
      router.replace('/login');
    }
  }, [user, loading, router]);

  // Enforce RBAC route guards
  useEffect(() => {
    if (!user) return;
    if (
      user.role === 'ADMIN' &&
      ADMIN_RESTRICTED.some((r) => pathname?.startsWith(r))
    ) {
      router.replace('/dashboard');
      return;
    }
    if (
      (user.role === 'CASEWORKER' || user.role === 'MANAGER') &&
      CASEWORKER_RESTRICTED.some((r) => pathname?.startsWith(r))
    ) {
      router.replace('/dashboard');
      return;
    }
    // Escalated cases: Managers only (Caseworker cannot access)
    if (user.role === 'CASEWORKER' && pathname === ESCALATED_ONLY_MANAGER) {
      router.replace('/dashboard');
    }
  }, [pathname, user, router]);

  if (loading || !user) {
    return (
      <div className="flex min-h-screen items-center justify-center bg-fast-bg">
        <div className="text-fast-muted text-sm">Loading...</div>
      </div>
    );
  }

  const navItems = user.role === 'ADMIN' ? adminNav : user.role === 'MANAGER' ? managerNav : caseworkerNav;

  // Unread notification count for badge (API first, fallback to mock)
  const { data: notificationsData } = useNotifications();
  const unreadCount = notificationsData?.notifications
    ? notificationsData.notifications.filter((n) => !n.read).length
    : getNotificationsForRole(user.role).filter((n) => !n.read).length;
  const navWithBadges = navItems.map((item) =>
    item.href === '/notifications' && unreadCount > 0
      ? { ...item, badge: unreadCount }
      : item
  );

  const initials = user.name
    .split(' ')
    .map((n) => n[0])
    .join('')
    .toUpperCase();

  const roleBadgeColor =
    user.role === 'ADMIN'      ? 'bg-fast-admin text-white' :
    user.role === 'MANAGER'    ? 'bg-fast-manager text-white' :
                                 'bg-fast-green-light text-fast-approved';

  const roleLabel =
    user.role === 'ADMIN'   ? 'Admin' :
    user.role === 'MANAGER' ? 'Manager' : 'Caseworker';

  return (
    <div className="flex min-h-screen bg-fast-bg">
      {/* Sidebar */}
      <aside className="w-64 bg-fast-sidebar flex flex-col flex-shrink-0">
        {/* Logo + User (requirements 6.2 Logo; specification Layout Logo) */}
        <div className="p-4 border-b border-white/10">
          <div className="flex items-center gap-2 mb-4">
            <img
              src="/version1-logo.svg"
              alt="Version 1"
              className="h-8 w-auto object-contain"
            />
            <div>
              <p className="text-[10px] font-semibold tracking-widest uppercase text-fast-cyan">VERSION 1</p>
              <p className="text-xs text-white font-medium">FastStartAI</p>
            </div>
          </div>
          <div className="flex items-center gap-3">
            <div className="w-10 h-10 bg-fast-caseworker rounded-full flex items-center justify-center text-white font-semibold text-sm">
              {initials}
            </div>
            <div className="flex-1 min-w-0">
              <p className="text-sm font-medium text-white truncate">{user.name}</p>
              <span className={`inline-block mt-0.5 px-2 py-0.5 text-xs font-medium rounded-full ${roleBadgeColor}`}>
                {roleLabel}
              </span>
            </div>
          </div>
        </div>

        {/* Nav */}
        <nav className="flex-1 p-2 space-y-1">
          {navWithBadges.map(({ href, label, icon, badge }) => {
            const isActive =
              pathname === href ||
              (href !== '/dashboard' && pathname?.startsWith(href));
            return (
              <Link
                key={href}
                href={href}
                className={cn(
                  'flex items-center gap-3 px-3 py-2.5 rounded-md text-sm font-medium transition-colors',
                  isActive
                    ? 'bg-fast-sidebar-active text-white'
                    : 'text-white/80 hover:bg-white/10 hover:text-white'
                )}
              >
                <span className="text-lg w-6 text-center">{icon}</span>
                <span className="flex-1">{label}</span>
                {badge !== undefined && badge > 0 && (
                  <span className="min-w-[20px] h-5 px-1 bg-fast-declined rounded-full flex items-center justify-center text-white text-xs font-semibold">
                    {badge}
                  </span>
                )}
              </Link>
            );
          })}
        </nav>

        {/* Sign Out */}
        <div className="p-4 border-t border-white/10">
          <button
            onClick={logout}
            className="w-full px-3 py-2 rounded-md text-sm font-medium text-white bg-fast-declined hover:bg-red-600 transition-colors"
          >
            Sign Out
          </button>
        </div>
      </aside>

      {/* Main content */}
      <main className="flex-1 overflow-auto bg-fast-bg">
        {children}
      </main>
    </div>
  );
}

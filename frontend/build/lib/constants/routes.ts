/**
 * Shared route constants – used by UI and any service that needs path references.
 */

export const ROUTES = {
  LOGIN: '/login',
  DASHBOARD: '/dashboard',
  CASES: '/cases',
  CASE_DETAIL: (id: string) => `/cases/${id}`,
  NOTIFICATIONS: '/notifications',
  SETTINGS: '/settings',
  ADMIN_USERS: '/admin/users',
  ADMIN_POLICIES: '/admin/policies',
} as const;

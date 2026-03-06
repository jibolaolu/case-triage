'use client';

import Link from 'next/link';

const nav = [
  { href: '/dashboard', label: 'Dashboard' },
  { href: '/cases', label: 'Cases' },
  { href: '/notifications', label: 'Notifications' },
  { href: '/settings', label: 'Settings' },
  { href: '/admin/users', label: 'User management' },
  { href: '/admin/policies', label: 'Policy management' },
];

export function Sidebar() {
  return (
    <aside className="w-56 border-r bg-gray-50 p-4">
      <nav className="space-y-1">
        {nav.map(({ href, label }) => (
          <Link
            key={href}
            href={href}
            className="block rounded px-3 py-2 text-sm font-medium text-gray-700 hover:bg-gray-100"
          >
            {label}
          </Link>
        ))}
      </nav>
    </aside>
  );
}

'use client';

import { useEffect } from 'react';
import Link from 'next/link';

export default function HomePage() {
  useEffect(() => {
    window.location.replace('/login');
  }, []);

  return (
    <div className="min-h-screen bg-fast-bg flex items-center justify-center p-6">
      <div className="text-center">
        <p className="text-fast-muted mb-2">Redirecting to login…</p>
        <Link href="/login" className="text-fast-teal font-medium hover:underline">
          Go to login
        </Link>
      </div>
    </div>
  );
}

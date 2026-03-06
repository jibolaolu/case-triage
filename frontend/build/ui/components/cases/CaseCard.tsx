'use client';

import Link from 'next/link';
import type { MockCase } from '@/types';

type CaseCardProps = { case: MockCase };

export function CaseCard({ case: c }: CaseCardProps) {
  const statusColors: Record<string, string> = {
    APPROVED:    'bg-fast-green-light text-fast-approved',
    DECLINED:    'bg-fast-red-light text-fast-declined',
    ESCALATED:   'bg-fast-orange-light text-fast-escalated',
    PENDING:     'bg-yellow-100 text-yellow-800',
    IN_PROGRESS: 'bg-fast-teal-light text-fast-teal',
  };

  const priorityColors: Record<string, string> = {
    URGENT:   'text-fast-urgent',
    HIGH:     'text-fast-high',
    STANDARD: 'text-fast-standard',
    LOW:      'text-fast-muted',
  };

  return (
    <Link
      href={`/cases/${c.id}`}
      className="block bg-fast-panel rounded-lg shadow-card p-4 hover:shadow-card-hover transition-shadow border-l-4 border-fast-teal"
    >
      <div className="flex items-start justify-between">
        <div className="flex-1">
          <span className="text-base font-semibold text-fast-teal">{c.id}</span>
          <div className="mt-2 flex items-center gap-2 flex-wrap">
            <span className={`px-2 py-0.5 rounded-full text-xs font-semibold ${statusColors[c.status] ?? 'bg-gray-100 text-fast-muted'}`}>
              {c.status.replace('_', ' ')}
            </span>
            <span className={`text-xs font-medium ${priorityColors[c.priority] ?? 'text-fast-muted'}`}>
              {c.priority}
            </span>
          </div>
          <p className="text-sm text-fast-text mt-2">{c.applicantName}</p>
          <p className="text-xs text-fast-muted mt-1">
            {new Date(c.updatedAt).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}
          </p>
        </div>
        <span className="text-fast-teal">👁️</span>
      </div>
    </Link>
  );
}

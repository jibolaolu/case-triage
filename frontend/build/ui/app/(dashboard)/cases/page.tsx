'use client';

import { useState, useMemo } from 'react';
import Link from 'next/link';
import { useCases } from '@/hooks/useCases';
import { mockCases } from '@/data/mockData';
import { StatusChip } from '@/components/ui';
import type { CaseStatus, Priority } from '@/types';

const PAGE_SIZE = 10;

const STATUS_OPTIONS: CaseStatus[] = ['PENDING', 'IN_PROGRESS', 'APPROVED', 'DECLINED', 'ESCALATED'];
const PRIORITY_OPTIONS: Priority[] = ['URGENT', 'HIGH', 'STANDARD', 'LOW'];

export default function CasesPage() {
  const [search, setSearch]         = useState('');
  const [statusFilter, setStatus]   = useState<string>('');
  const [priorityFilter, setPriority] = useState<string>('');
  const [page, setPage]             = useState(1);

  const { data: apiData, isLoading, isError, error } = useCases({
    status: statusFilter || undefined,
    limit: 100,
  });

  const cases = (() => {
    if (isError) return [];
    if (apiData?.cases && Array.isArray(apiData.cases)) {
      return apiData.cases.map((c) => ({
        id: c.caseId,
        applicantName: c.applicantName,
        applicationType: c.applicationType,
        status: c.status,
        priority: c.priority,
        assignedTo: c.assignedTo,
        assignedToName: c.assignedToName,
        createdAt: c.createdAt,
        updatedAt: c.updatedAt,
        aiConfidence: c.aiConfidence,
      }));
    }
    return mockCases;
  })();

  const filtered = useMemo(() => {
    return cases.filter((c) => {
      const q = search.toLowerCase();
      const matchSearch =
        !q ||
        c.id.toLowerCase().includes(q) ||
        c.applicantName.toLowerCase().includes(q);
      const matchStatus   = !statusFilter   || c.status   === statusFilter;
      const matchPriority = !priorityFilter || c.priority === priorityFilter;
      return matchSearch && matchStatus && matchPriority;
    });
  }, [cases, search, statusFilter, priorityFilter]);

  const totalPages = Math.ceil(filtered.length / PAGE_SIZE);
  const paginated  = filtered.slice((page - 1) * PAGE_SIZE, page * PAGE_SIZE);

  const resetPage = () => setPage(1);

  if (isLoading) {
    return (
      <div className="p-6">
        <div className="flex items-center justify-center py-12 text-fast-muted text-sm">Loading cases…</div>
      </div>
    );
  }

  return (
    <div className="p-6">
      {/* API error: e.g. 401 when not signed in with Cognito — show message so new cases from API are not hidden by mock */}
      {isError && (
        <div className="mb-4 rounded-lg border border-amber-300 bg-amber-50 p-4 text-amber-800">
          <p className="font-semibold">Could not load cases from server</p>
          <p className="text-sm mt-1">
            {error instanceof Error ? error.message : 'Request failed.'}
            {' '}Ensure <code className="bg-amber-100 px-1 rounded">NEXT_PUBLIC_API_URL</code> points to your API Gateway and sign in with Cognito to load real cases (including new ones from intake).
          </p>
          <p className="text-xs mt-2 text-amber-700">
            Showing empty list. Fix the connection or sign in with Cognito to see cases.
          </p>
        </div>
      )}

      {/* Header */}
      <div className="mb-6">
        <div className="flex items-center gap-2 mb-1">
          <span className="text-2xl">📁</span>
          <h1 className="text-3xl font-bold text-fast-teal">Case Management</h1>
        </div>
        <p className="text-base text-fast-muted">Review and manage all assigned cases</p>
      </div>

      {/* Filters */}
      <div className="mb-4 bg-fast-panel rounded-lg shadow-card p-4">
        <div className="flex flex-wrap items-center gap-3">
          <div className="relative flex-1 min-w-48">
            <input
              type="text"
              value={search}
              onChange={(e) => { setSearch(e.target.value); resetPage(); }}
              placeholder="Search by case ID or applicant name…"
              className="w-full px-4 py-2 pl-9 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal"
            />
            <span className="absolute left-3 top-2.5 text-fast-muted text-sm">🔍</span>
          </div>
          <select
            value={statusFilter}
            onChange={(e) => { setStatus(e.target.value); resetPage(); }}
            className="px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal"
          >
            <option value="">All Statuses</option>
            {STATUS_OPTIONS.map((s) => (
              <option key={s} value={s}>{s.replace('_', ' ')}</option>
            ))}
          </select>
          <select
            value={priorityFilter}
            onChange={(e) => { setPriority(e.target.value); resetPage(); }}
            className="px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal"
          >
            <option value="">All Priorities</option>
            {PRIORITY_OPTIONS.map((p) => (
              <option key={p} value={p}>{p}</option>
            ))}
          </select>
          {(search || statusFilter || priorityFilter) && (
            <button
              onClick={() => { setSearch(''); setStatus(''); setPriority(''); resetPage(); }}
              className="px-3 py-2 text-sm text-fast-muted hover:text-fast-text"
            >
              Clear
            </button>
          )}
        </div>
      </div>

      {/* Table */}
      <div className="bg-fast-panel rounded-lg shadow-card overflow-hidden">
        <table className="min-w-full">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Case ID</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Applicant</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Type</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Status</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Priority</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Assigned To</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Updated</th>
              <th className="px-4 py-3 text-right text-xs font-medium text-fast-muted uppercase">AI Confidence</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {paginated.length === 0 ? (
              <tr>
                <td colSpan={8} className="px-4 py-10 text-center text-fast-muted text-sm">
                  No cases match your filters.
                </td>
              </tr>
            ) : (
              paginated.map((c) => (
                <tr key={c.id} className="hover:bg-gray-50 cursor-pointer">
                  <td className="px-4 py-3">
                    <Link
                      href={`/cases/${c.id}`}
                      className="text-sm font-semibold text-fast-teal hover:underline"
                    >
                      {c.id}
                    </Link>
                  </td>
                  <td className="px-4 py-3 text-sm text-fast-text">{c.applicantName}</td>
                  <td className="px-4 py-3 text-sm text-fast-text">{c.applicationType}</td>
                  <td className="px-4 py-3">
                    <StatusChip status={c.status} size="sm" />
                  </td>
                  <td className="px-4 py-3">
                    <span className={`text-sm font-medium ${
                      c.priority === 'URGENT'   ? 'text-fast-urgent' :
                      c.priority === 'HIGH'     ? 'text-fast-high' :
                      c.priority === 'STANDARD' ? 'text-fast-standard' :
                                                  'text-fast-muted'
                    }`}>
                      {c.priority}
                    </span>
                  </td>
                  <td className="px-4 py-3 text-sm text-fast-text">{c.assignedToName}</td>
                  <td className="px-4 py-3 text-sm text-fast-muted">
                    {new Date(c.updatedAt).toLocaleDateString('en-GB', {
                      day: '2-digit', month: 'short', year: 'numeric',
                    })}
                  </td>
                  <td className="px-4 py-3 text-sm text-right">
                    {c.aiConfidence !== undefined ? (
                      <span className={c.aiConfidence < 50 ? 'text-fast-declined font-medium' : 'text-fast-approved font-medium'}>
                        {c.aiConfidence}%
                      </span>
                    ) : (
                      <span className="text-fast-muted">—</span>
                    )}
                  </td>
                </tr>
              ))
            )}
          </tbody>
        </table>

        {/* Pagination */}
        {totalPages > 1 && (
          <div className="px-4 py-3 border-t border-gray-200 flex justify-between items-center bg-gray-50">
            <button
              onClick={() => setPage((p) => Math.max(1, p - 1))}
              disabled={page === 1}
              className="px-3 py-1 text-sm text-fast-muted hover:text-fast-text disabled:opacity-40"
            >
              ← Previous
            </button>
            <div className="flex gap-1">
              {Array.from({ length: totalPages }, (_, i) => i + 1).map((p) => (
                <button
                  key={p}
                  onClick={() => setPage(p)}
                  className={`w-8 h-8 rounded-md text-sm font-medium ${
                    p === page
                      ? 'bg-fast-teal text-white'
                      : 'text-fast-text hover:bg-gray-100'
                  }`}
                >
                  {p}
                </button>
              ))}
            </div>
            <button
              onClick={() => setPage((p) => Math.min(totalPages, p + 1))}
              disabled={page === totalPages}
              className="px-3 py-1 text-sm text-fast-muted hover:text-fast-text disabled:opacity-40"
            >
              Next →
            </button>
          </div>
        )}

        <div className="px-4 py-2 border-t border-gray-100 bg-gray-50">
          <p className="text-xs text-fast-muted">
            Showing {paginated.length} of {filtered.length} cases
          </p>
        </div>
      </div>
    </div>
  );
}

'use client';

import { useAuth } from '@/contexts/AuthContext';
import { useCases } from '@/hooks/useCases';
import { mockCases } from '@/data/mockData';

export default function DashboardPage() {
  const { user } = useAuth();

  const { data: apiData } = useCases({ limit: 100 });
  const allCases =
    apiData?.cases?.map((c) => ({
      id: c.caseId,
      status: c.status,
      priority: c.priority,
      assignedTo: c.assignedTo,
      applicantName: c.applicantName,
      assignedToName: c.assignedToName || '',
    })) ?? mockCases;

  // Compute stats from API data or mock
  const myCases = user
    ? allCases.filter((c) => c.assignedTo === user.id)
    : allCases;

  const total     = myCases.length;
  const pending   = myCases.filter((c) => c.status === 'PENDING').length;
  const inProg    = myCases.filter((c) => c.status === 'IN_PROGRESS').length;
  const approved  = myCases.filter((c) => c.status === 'APPROVED').length;
  const declined  = myCases.filter((c) => c.status === 'DECLINED').length;
  const escalated = myCases.filter((c) => c.status === 'ESCALATED').length;

  const urgent   = myCases.filter((c) => c.priority === 'URGENT').length;
  const high     = myCases.filter((c) => c.priority === 'HIGH').length;
  const standard = myCases.filter((c) => c.priority === 'STANDARD').length;
  const low      = myCases.filter((c) => c.priority === 'LOW').length;

  const priorityMax = Math.max(urgent, high, standard, low, 1);

  const statCards = [
    { label: 'Total Cases',  value: total,    color: 'border-fast-teal',        icon: '📊', iconBg: 'bg-fast-teal-light',   iconColor: 'text-fast-teal', sub: 'All assigned cases' },
    { label: 'In Progress',  value: inProg,   color: 'border-fast-pending',    icon: '⏳', iconBg: 'bg-yellow-100', iconColor: 'text-yellow-600', sub: 'Actively being reviewed' },
    { label: 'Approved',     value: approved, color: 'border-fast-approved',   icon: '✓',  iconBg: 'bg-fast-green-light', iconColor: 'text-fast-approved', sub: 'Successfully processed' },
    { label: 'Escalated',    value: escalated,color: 'border-fast-escalated',  icon: '⚠️', iconBg: 'bg-orange-100', iconColor: 'text-fast-escalated', sub: escalated > 0 ? 'Needs attention' : 'No escalations' },
  ];

  const statusBars = [
    { label: 'Pending',     count: pending,   color: 'bg-yellow-400' },
    { label: 'In Progress', count: inProg,    color: 'bg-fast-teal' },
    { label: 'Approved',    count: approved,  color: 'bg-fast-approved' },
    { label: 'Declined',    count: declined,  color: 'bg-fast-declined' },
    { label: 'Escalated',   count: escalated, color: 'bg-fast-escalated' },
  ];

  const priorityBars = [
    { label: 'Urgent',   count: urgent,   color: 'bg-fast-urgent' },
    { label: 'High',     count: high,     color: 'bg-fast-high' },
    { label: 'Standard', count: standard, color: 'bg-fast-standard' },
    { label: 'Low',      count: low,      color: 'bg-gray-400' },
  ];

  return (
    <div className="p-6">
      <div className="mb-6">
        <h1 className="text-3xl font-bold text-fast-teal mb-1">Analytics Dashboard</h1>
        <p className="text-base text-fast-muted">
          Welcome back, {user?.name ?? 'User'}. Here&apos;s your performance overview.
        </p>
      </div>

      {/* Summary cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4 mb-6">
        {statCards.map((card) => (
          <div
            key={card.label}
            className={`bg-fast-panel rounded-lg shadow-card p-5 border-l-4 ${card.color}`}
          >
            <div className="flex items-center justify-between mb-2">
              <p className="text-sm font-medium text-fast-muted">{card.label}</p>
              <div className={`w-10 h-10 ${card.iconBg} rounded-full flex items-center justify-center`}>
                <span className={`${card.iconColor} text-xl`}>{card.icon}</span>
              </div>
            </div>
            <p className="text-3xl font-bold text-fast-text mb-1">{card.value}</p>
            <p className={`text-xs font-medium ${card.label === 'Escalated' && escalated > 0 ? 'text-fast-escalated' : 'text-fast-muted'}`}>
              {card.sub}
            </p>
          </div>
        ))}
      </div>

      {/* Charts */}
      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        {/* Status Distribution */}
        <div className="bg-fast-panel rounded-lg shadow-card p-6">
          <h2 className="text-xl font-bold text-fast-teal mb-4">Case Status Distribution</h2>
          <div className="space-y-3">
            {statusBars.map((item) => (
              <div key={item.label} className="flex items-center gap-3">
                <div className={`w-3 h-3 rounded-full ${item.color}`} />
                <span className="text-sm text-fast-text w-24">{item.label}</span>
                <div className="flex-1 h-2 bg-gray-200 rounded-full overflow-hidden">
                  <div
                    className={`h-full ${item.color}`}
                    style={{ width: total > 0 ? `${(item.count / total) * 100}%` : '0%' }}
                  />
                </div>
                <span className="text-sm text-fast-muted w-16 text-right">
                  {item.count} ({total > 0 ? Math.round((item.count / total) * 100) : 0}%)
                </span>
              </div>
            ))}
          </div>
        </div>

        {/* Priority Distribution */}
        <div className="bg-fast-panel rounded-lg shadow-card p-6">
          <h2 className="text-xl font-bold text-fast-teal mb-4">Priority Distribution</h2>
          <div className="space-y-3">
            {priorityBars.map((item) => (
              <div key={item.label} className="flex items-center gap-3">
                <span className="text-sm text-fast-text w-16">{item.label}</span>
                <div className="flex-1 h-2 bg-gray-200 rounded-full overflow-hidden">
                  <div
                    className={`h-full ${item.color}`}
                    style={{ width: `${(item.count / priorityMax) * 100}%` }}
                  />
                </div>
                <span className="text-sm text-fast-muted w-6 text-right">{item.count}</span>
              </div>
            ))}
          </div>
        </div>
      </div>

      {/* Recent Activity */}
      <div className="mt-6 bg-fast-panel rounded-lg shadow-card p-6">
        <h2 className="text-xl font-bold text-fast-teal mb-4">Recent Cases</h2>
        <div className="overflow-x-auto">
          <table className="min-w-full">
            <thead>
              <tr className="border-b border-gray-200">
                <th className="pb-2 text-left text-xs font-medium text-fast-muted uppercase">Case ID</th>
                <th className="pb-2 text-left text-xs font-medium text-fast-muted uppercase">Applicant</th>
                <th className="pb-2 text-left text-xs font-medium text-fast-muted uppercase">Status</th>
                <th className="pb-2 text-left text-xs font-medium text-fast-muted uppercase">Priority</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-gray-100">
              {myCases.slice(0, 5).map((c) => (
                <tr key={c.id} className="hover:bg-gray-50">
                  <td className="py-2 text-sm font-medium text-fast-teal">{c.id}</td>
                  <td className="py-2 text-sm text-fast-text">{c.applicantName}</td>
                  <td className="py-2">
                    <span className={`px-2 py-0.5 text-xs font-semibold rounded-full ${
                      c.status === 'APPROVED'    ? 'bg-fast-green-light text-fast-approved' :
                      c.status === 'DECLINED'    ? 'bg-fast-red-light text-fast-declined' :
                      c.status === 'ESCALATED'   ? 'bg-fast-orange-light text-fast-escalated' :
                      c.status === 'IN_PROGRESS' ? 'bg-fast-teal-light text-fast-teal' :
                                                   'bg-yellow-100 text-yellow-800'
                    }`}>
                      {c.status.replace('_', ' ')}
                    </span>
                  </td>
                  <td className="py-2 text-sm font-medium" style={{
                    color: c.priority === 'URGENT' ? '#f44336' : c.priority === 'HIGH' ? '#ff9800' : '#607d8b'
                  }}>
                    {c.priority}
                  </td>
                </tr>
              ))}
              {myCases.length === 0 && (
                <tr>
                  <td colSpan={4} className="py-6 text-center text-fast-muted text-sm">
                    No cases assigned to you.
                  </td>
                </tr>
              )}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
}

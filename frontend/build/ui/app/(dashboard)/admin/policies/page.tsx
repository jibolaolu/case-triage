'use client';

import { useState, useMemo, useEffect } from 'react';
import { usePolicies, useDeletePolicy } from '@/hooks/usePolicies';

type PolicyItem = {
  id: string;
  name: string;
  category: string;
  version: string;
  status: 'active' | 'expiring' | 'expired';
  filename: string;
  size: string;
  date: string;
  effectiveTo: string; // ISO date for expiry
  uploader: string;
  /** Sample content for view (in real app would be fetched from S3/API) */
  content?: string;
};

const sampleYaml = (name: string, category: string) =>
  `# ${name}\n# Category: ${category}\n# AI policy definition – used by case evaluation agents\n\npolicy:\n  id: policy-${name.toLowerCase().replace(/\s+/g, '-')}\n  version: 1.0\n  rules:\n    - name: eligibility_check\n      type: eligibility\n      conditions:\n        - field: documents_complete\n          operator: eq\n          value: true\n    - name: income_threshold\n      type: threshold\n      conditions:\n        - field: household_income\n          operator: lte\n          value: 25000\n  required_documents:\n    - proof_of_identity\n    - proof_of_address\n    - income_statement\n`;

const initialPolicies: PolicyItem[] = [
  { id: 'p1', name: 'Housing Eligibility Policy', category: 'Eligibility', version: 'v2.1.0', status: 'active', filename: 'housing-eligibility-v2.1.yaml', size: '45 KB', date: 'Jan 15, 2026', effectiveTo: '2026-12-31', uploader: 'Admin User', content: sampleYaml('Housing Eligibility Policy', 'Eligibility') },
  { id: 'p2', name: 'Document Verification Policy', category: 'Verification', version: 'v1.5.0', status: 'expiring', filename: 'doc-verification-v1.5.yaml', size: '32 KB', date: 'Jan 10, 2026', effectiveTo: new Date(Date.now() + 20 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10), uploader: 'Admin User', content: sampleYaml('Document Verification Policy', 'Verification') },
  { id: 'p3', name: 'Support Scheme Policy', category: 'Documentation', version: 'v3.0.0', status: 'active', filename: 'support-scheme-v3.yaml', size: '58 KB', date: 'Feb 1, 2026', effectiveTo: '2026-11-30', uploader: 'Admin User', content: sampleYaml('Support Scheme Policy', 'Documentation') },
  { id: 'p4', name: 'Income Threshold Policy', category: 'Eligibility', version: 'v1.0.0', status: 'expired', filename: 'income-threshold-v1.yaml', size: '28 KB', date: 'Aug 1, 2025', effectiveTo: new Date(Date.now() - 10 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10), uploader: 'Admin User', content: sampleYaml('Income Threshold Policy', 'Eligibility') },
  { id: 'p5', name: 'Legacy Verification Policy', category: 'Verification', version: 'v0.9.0', status: 'expired', filename: 'legacy-verification.yaml', size: '22 KB', date: 'Jun 15, 2025', effectiveTo: new Date(Date.now() - 60 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10), uploader: 'Admin User', content: sampleYaml('Legacy Verification Policy', 'Verification') },
];

function getStatus(effectiveTo: string): 'active' | 'expiring' | 'expired' {
  const now = new Date();
  const to = new Date(effectiveTo);
  const daysLeft = (to.getTime() - now.getTime()) / (24 * 60 * 60 * 1000);
  if (daysLeft < 0) return 'expired';
  if (daysLeft <= 30) return 'expiring';
  return 'active';
}

/** Map API policy to PolicyItem for display. */
function apiPolicyToItem(p: { id: string; name?: string; category?: string; version?: string; status?: string; createdAt?: string }): PolicyItem {
  const name = p.name || p.id;
  const effectiveTo = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
  return {
    id: p.id,
    name,
    category: p.category || 'General',
    version: p.version || '1.0',
    status: getStatus(effectiveTo),
    filename: `${(name || p.id).toLowerCase().replace(/\s+/g, '-')}.yaml`,
    size: '—',
    date: p.createdAt ? new Date(p.createdAt).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' }) : '—',
    effectiveTo,
    uploader: 'System',
    content: undefined,
  };
}

export default function AdminPoliciesPage() {
  const { data: policiesData } = usePolicies();
  const deletePolicyMutation = useDeletePolicy();

  const apiPoliciesList = useMemo(
    () => (policiesData?.policies?.length ? policiesData.policies.map((p) => apiPolicyToItem(p as Parameters<typeof apiPolicyToItem>[0])) : []),
    [policiesData]
  );

  const [localPolicies, setLocalPolicies] = useState<PolicyItem[]>(() =>
    initialPolicies.map((p) => ({ ...p, status: getStatus(p.effectiveTo) }))
  );

  const policies = apiPoliciesList.length > 0 ? apiPoliciesList : localPolicies;

  useEffect(() => {
    if (apiPoliciesList.length > 0) return;
    setLocalPolicies((prev) =>
      prev.map((p) => ({ ...p, status: getStatus(p.effectiveTo) }))
    );
  }, [apiPoliciesList.length]);

  const [editPolicy, setEditPolicy] = useState<PolicyItem | null>(null);
  const [deleteConfirm, setDeleteConfirm] = useState<PolicyItem | null>(null);
  const [viewPolicy, setViewPolicy] = useState<PolicyItem | null>(null);

  const activePolicies = policies.filter((p) => p.status === 'active');
  const aboutToExpire = policies.filter((p) => p.status === 'expiring');
  const expiredPolicies = policies.filter((p) => p.status === 'expired');

  const handleDelete = (policy: PolicyItem) => {
    if (apiPoliciesList.length > 0) {
      deletePolicyMutation.mutate(policy.id, { onSettled: () => setDeleteConfirm(null) });
    } else {
      setLocalPolicies((prev) => prev.filter((p) => p.id !== policy.id));
      setDeleteConfirm(null);
    }
  };

  const handleEditSave = (updated: { name: string; category: string }) => {
    if (!editPolicy) return;
    if (apiPoliciesList.length === 0) {
      setLocalPolicies((prev) =>
        prev.map((p) => (p.id === editPolicy.id ? { ...p, name: updated.name, category: updated.category } : p))
      );
    }
    setEditPolicy(null);
  };

  const renderPolicyCard = (policy: PolicyItem, showActions = true) => (
    <div key={policy.id} className="bg-fast-panel rounded-lg shadow-card p-5">
      <div className="flex items-start justify-between mb-3">
        <span
          className={`px-2 py-1 rounded-full text-xs font-bold ${
            policy.status === 'active'
              ? 'bg-fast-green-light text-fast-approved'
              : policy.status === 'expiring'
              ? 'bg-yellow-100 text-yellow-800'
              : 'bg-gray-200 text-fast-muted'
          }`}
        >
          {policy.status === 'expiring' ? 'expiring soon' : policy.status}
        </span>
        <span className="text-xs text-fast-muted">{policy.version}</span>
      </div>
      <h3 className="text-base font-bold text-fast-text mb-2">{policy.name}</h3>
      <span className="inline-block px-2 py-1 bg-fast-purple-light text-purple-700 rounded-full text-xs font-medium mb-3">
        {policy.category}
      </span>
      <div className="space-y-2 mb-4">
        <div className="flex items-center gap-2 text-sm">
          <span className="text-fast-muted">📄</span>
          <span className="text-fast-text">{policy.filename}</span>
        </div>
        <div className="flex items-center justify-between text-xs text-fast-muted">
          <span>{policy.size}</span>
          <span>{policy.date}</span>
        </div>
        <div className="text-xs text-fast-muted">
          Expires: {new Date(policy.effectiveTo).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}
        </div>
      </div>
      <div className="flex items-center gap-2 mb-4 text-xs text-fast-muted">
        <span className="w-6 h-6 bg-gray-200 rounded-full flex items-center justify-center font-semibold">AU</span>
        <span>Uploaded by {policy.uploader}</span>
      </div>
      {showActions && (
        <div className="flex gap-2">
          <button
            onClick={() => setViewPolicy(policy)}
            className="flex-1 px-3 py-2 bg-fast-teal text-white rounded-md text-sm font-semibold hover:opacity-90 transition-colors flex items-center justify-center gap-1"
          >
            <span>👁️</span> View
          </button>
          <button
            onClick={() => setEditPolicy(policy)}
            className="px-3 py-2 bg-gray-100 hover:bg-gray-200 rounded-md text-sm"
            title="Edit"
          >
            ✏️
          </button>
          <button
            onClick={() => setDeleteConfirm(policy)}
            className="px-3 py-2 bg-gray-100 hover:bg-gray-200 rounded-md text-sm hover:bg-red-50"
            title="Delete"
          >
            🗑️
          </button>
        </div>
      )}
    </div>
  );

  return (
    <div className="p-6">
      <div className="mb-6 flex items-center justify-between">
        <div>
          <div className="flex items-center gap-2 mb-2">
            <span className="text-2xl">📋</span>
            <h1 className="text-3xl font-bold text-fast-teal">AI Policy Management</h1>
          </div>
          <p className="text-base text-fast-muted">Upload, edit, and delete policies. View about-to-expire and expired policies.</p>
        </div>
        <button className="px-4 py-2 bg-fast-approved text-white rounded-md font-semibold hover:bg-fast-teal transition-colors flex items-center gap-2">
          <span>📤</span>
          Upload New Policy
        </button>
      </div>

      <div className="bg-fast-teal-light border border-fast-teal/30 rounded-lg p-4 mb-6">
        <h3 className="text-base font-semibold text-fast-teal mb-2">How AI Policies Work</h3>
        <ul className="text-sm text-fast-text space-y-1 list-disc list-inside">
          <li>Policies define eligibility rules and required documents</li>
          <li>AI agents use policies to validate and evaluate cases</li>
          <li>Policies are versioned; you can upload, edit, and delete</li>
          <li>Review about-to-expire and expired policies for renewal</li>
        </ul>
      </div>

      {/* About to expire */}
      {aboutToExpire.length > 0 && (
        <div className="mb-6">
          <h2 className="text-xl font-bold text-yellow-700 mb-4">About to expire (within 30 days)</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {aboutToExpire.map((p) => renderPolicyCard(p))}
          </div>
        </div>
      )}

      {/* Expired */}
      {expiredPolicies.length > 0 && (
        <div className="mb-6">
          <h2 className="text-xl font-bold text-fast-muted mb-4">Expired policies</h2>
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {expiredPolicies.map((p) => renderPolicyCard(p))}
          </div>
        </div>
      )}

      {/* Active */}
      <div className="mb-6">
        <h2 className="text-xl font-bold text-fast-approved mb-4">Active AI Policies</h2>
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {activePolicies.length === 0 ? (
            <p className="text-fast-muted text-sm col-span-full">No active policies.</p>
          ) : (
            activePolicies.map((p) => renderPolicyCard(p))
          )}
        </div>
      </div>

      {/* Policy Versions Table */}
      <div className="bg-fast-panel rounded-lg shadow-card overflow-hidden">
        <div className="p-4 border-b border-gray-200">
          <h2 className="text-lg font-semibold text-fast-text">Policy Versions</h2>
        </div>
        <table className="min-w-full">
          <thead className="bg-gray-50">
            <tr>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Version</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Status</th>
              <th className="px-4 py-3 text-left text-xs font-medium text-fast-muted uppercase">Expires</th>
              <th className="px-4 py-3 text-right text-xs font-medium text-fast-muted uppercase">Actions</th>
            </tr>
          </thead>
          <tbody className="divide-y divide-gray-200">
            {policies.map((p) => (
              <tr key={p.id}>
                <td className="px-4 py-3 text-sm text-fast-text">{p.version}</td>
                <td className="px-4 py-3">
                  <span className={`px-2 py-0.5 rounded-full text-xs font-medium ${
                    p.status === 'active' ? 'bg-fast-green-light text-fast-approved' : p.status === 'expiring' ? 'bg-yellow-100 text-yellow-800' : 'bg-gray-200 text-fast-muted'
                  }`}>
                    {p.status}
                  </span>
                </td>
                <td className="px-4 py-3 text-sm text-fast-muted">{new Date(p.effectiveTo).toLocaleDateString('en-GB')}</td>
                <td className="px-4 py-3 text-right">
                  <button onClick={() => setViewPolicy(p)} className="text-fast-teal hover:underline text-sm mr-2">View</button>
                  <button onClick={() => setEditPolicy(p)} className="text-fast-teal hover:underline text-sm mr-2">Edit</button>
                  <button onClick={() => setDeleteConfirm(p)} className="text-fast-declined hover:underline text-sm">Delete</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {/* Edit modal */}
      {editPolicy && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-fast-panel rounded-lg shadow-xl max-w-md w-full p-6">
            <h3 className="text-lg font-bold text-fast-teal mb-4">Edit policy</h3>
            <EditForm
              name={editPolicy.name}
              category={editPolicy.category}
              onSave={handleEditSave}
              onCancel={() => setEditPolicy(null)}
            />
          </div>
        </div>
      )}

      {/* View policy modal */}
      {viewPolicy && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-fast-panel rounded-lg shadow-xl max-w-4xl w-full max-h-[90vh] flex flex-col">
            <div className="p-4 border-b border-gray-200 flex items-center justify-between flex-shrink-0">
              <div>
                <h3 className="text-lg font-bold text-fast-teal">{viewPolicy.name}</h3>
                <p className="text-sm text-fast-muted mt-0.5">
                  {viewPolicy.filename} · {viewPolicy.version} · {viewPolicy.category}
                </p>
              </div>
              <button
                onClick={() => setViewPolicy(null)}
                className="text-fast-muted hover:text-fast-text text-2xl leading-none p-1"
                aria-label="Close"
              >
                ×
              </button>
            </div>
            <div className="p-4 overflow-auto flex-1 min-h-0">
              <pre className="text-sm text-fast-text font-mono whitespace-pre-wrap bg-gray-50 border border-gray-200 rounded-lg p-4">
                {viewPolicy.content ?? `# ${viewPolicy.name}\n\nNo content available.`}
              </pre>
            </div>
          </div>
        </div>
      )}

      {/* Delete confirm */}
      {deleteConfirm && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-fast-panel rounded-lg shadow-xl max-w-md w-full p-6">
            <h3 className="text-lg font-bold text-fast-teal mb-2">Delete policy?</h3>
            <p className="text-sm text-fast-muted mb-4">
              &quot;{deleteConfirm.name}&quot; ({deleteConfirm.version}) will be removed. This cannot be undone.
            </p>
            <div className="flex gap-3">
              <button
                onClick={() => setDeleteConfirm(null)}
                className="flex-1 px-4 py-2 border border-gray-200 rounded-md font-medium text-fast-text hover:bg-gray-50"
              >
                Cancel
              </button>
              <button
                onClick={() => handleDelete(deleteConfirm)}
                className="flex-1 px-4 py-2 bg-fast-declined text-white rounded-md font-semibold hover:bg-red-600"
              >
                Delete
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function EditForm({
  name,
  category,
  onSave,
  onCancel,
}: {
  name: string;
  category: string;
  onSave: (v: { name: string; category: string }) => void;
  onCancel: () => void;
}) {
  const [editName, setEditName] = useState(name);
  const [editCategory, setEditCategory] = useState(category);
  return (
    <>
      <div className="space-y-4 mb-6">
        <div>
          <label className="block text-sm font-medium text-fast-text mb-1">Policy name</label>
          <input
            type="text"
            value={editName}
            onChange={(e) => setEditName(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
          />
        </div>
        <div>
          <label className="block text-sm font-medium text-fast-text mb-1">Category</label>
          <select
            value={editCategory}
            onChange={(e) => setEditCategory(e.target.value)}
            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm"
          >
            <option value="Eligibility">Eligibility</option>
            <option value="Verification">Verification</option>
            <option value="Documentation">Documentation</option>
          </select>
        </div>
      </div>
      <div className="flex gap-3">
        <button onClick={onCancel} className="flex-1 px-4 py-2 border border-gray-200 rounded-md font-medium text-fast-text hover:bg-gray-50">
          Cancel
        </button>
        <button
          onClick={() => onSave({ name: editName, category: editCategory })}
          className="flex-1 px-4 py-2 bg-fast-teal text-white rounded-md font-semibold hover:opacity-90"
        >
          Save
        </button>
      </div>
    </>
  );
}

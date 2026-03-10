'use client';

import { useParams, useRouter } from 'next/navigation';
import Link from 'next/link';
import { useCaseDetail } from '@/hooks/useCaseDetail';
import { getCaseById } from '@/data/mockData';
import { StatusChip } from '@/components/ui';
import { DecisionPanel } from '@/components/cases';
import { useAuth } from '@/contexts/AuthContext';

export default function CaseDetailPage() {
  const params = useParams();
  const router = useRouter();
  const { user } = useAuth();
  const id = params?.id as string;

  const { data: apiCaseData, isLoading } = useCaseDetail(id);
  const caseData = apiCaseData
    ? withApplicantDisplayFields({
        ...apiCaseData,
        id: apiCaseData.caseId || id,
      })
    : getCaseById(id);

  if (isLoading) {
    return (
      <div className="p-6">
        <div className="flex items-center justify-center py-12 text-fast-muted text-sm">Loading case…</div>
      </div>
    );
  }

  if (!caseData) {
    return (
      <div className="p-6">
        <Link href="/cases" className="inline-flex items-center gap-1 text-fast-teal hover:underline mb-4 text-sm">
          ← Back to Cases
        </Link>
        <div className="bg-fast-panel rounded-lg shadow-card p-10 text-center">
          <p className="text-fast-muted text-sm">Case <strong>{id}</strong> was not found.</p>
          <button
            onClick={() => router.push('/cases')}
            className="mt-4 px-4 py-2 bg-fast-teal text-white rounded-md text-sm font-medium"
          >
            Return to Case List
          </button>
        </div>
      </div>
    );
  }

  const isEscalated = caseData.status === 'ESCALATED';
  const isDecided   = caseData.status === 'APPROVED' || caseData.status === 'DECLINED';

  const statusPanelStyles: Record<string, { container: string; iconBg: string; iconText: string; icon: string }> = {
    APPROVED:  { container: 'bg-fast-green-light border-fast-approved', iconBg: 'bg-fast-approved', iconText: 'text-white', icon: '✓' },
    DECLINED:  { container: 'bg-fast-red-light border-fast-declined',   iconBg: 'bg-fast-declined', iconText: 'text-white', icon: '✕' },
    ESCALATED: { container: 'bg-fast-orange-light border-fast-escalated', iconBg: 'bg-fast-escalated', iconText: 'text-white', icon: '⚠' },
    PENDING:   { container: 'bg-yellow-50 border-yellow-300',            iconBg: 'bg-yellow-400', iconText: 'text-white', icon: '⏳' },
    IN_PROGRESS: { container: 'bg-fast-teal-light border-fast-teal', iconBg: 'bg-fast-teal', iconText: 'text-white', icon: '🔄' },
  };

  const panel = statusPanelStyles[caseData.status] ?? statusPanelStyles['PENDING'];

  return (
    <div className="p-6">
      {/* Back link */}
      <Link
        href={isEscalated ? '/escalated' : '/cases'}
        className="inline-flex items-center gap-1 text-fast-teal hover:underline mb-4 text-sm"
      >
        ← Back to {isEscalated ? 'Escalated Cases' : 'Cases'}
      </Link>

      {/* Case header */}
      <div className="mb-4 flex flex-wrap items-center gap-3">
        <h1 className="text-2xl font-bold text-fast-teal">{caseData.id}</h1>
        <StatusChip status={caseData.status} size="md" />
        <StatusChip status={caseData.priority} size="sm" />
      </div>

      {/* AI recommendation outcome — highlighted at top when present */}
      {caseData.aiRecommendation && (
        <div className="mb-6 rounded-lg border-2 border-fast-teal bg-fast-teal/5 p-4 flex items-center gap-4">
          <div className={`w-12 h-12 rounded-full flex items-center justify-center text-xl font-bold text-white flex-shrink-0 ${
            caseData.aiRecommendation === 'APPROVE' ? 'bg-fast-approved' : 'bg-fast-declined'
          }`}>
            {caseData.aiRecommendation === 'APPROVE' ? '✓' : '✕'}
          </div>
          <div className="min-w-0">
            <p className="text-sm font-semibold text-fast-muted uppercase tracking-wide">AI recommendation</p>
            <p className="text-lg font-bold text-fast-text mt-0.5">
              Outcome: {caseData.aiRecommendation}
              {caseData.aiConfidence != null && (
                <span className="ml-2 text-base font-normal text-fast-muted">({caseData.aiConfidence}% confidence)</span>
              )}
            </p>
          </div>
        </div>
      )}

      {/* Status banner */}
      <div className={`mb-6 border-2 rounded-lg p-4 flex items-center gap-4 ${panel.container}`}>
        <div className={`w-10 h-10 ${panel.iconBg} rounded-full flex items-center justify-center text-lg ${panel.iconText} flex-shrink-0`}>
          {panel.icon}
        </div>
        <div>
          <p className="font-semibold text-fast-text">
            Case Status: {caseData.status.replace('_', ' ')}
          </p>
          {isEscalated && caseData.escalationReason && (
            <p className="text-sm text-fast-muted mt-0.5">
              Escalation Reason: {caseData.escalationReason}
            </p>
          )}
          {isDecided && (
            <p className="text-sm text-fast-muted mt-0.5">
              This case has been {caseData.status.toLowerCase()}. No further action required.
            </p>
          )}
        </div>
      </div>

      {/* Main content grid */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Left column */}
        <div className="lg:col-span-2 space-y-6">
          {/* Applicant Information */}
          <div className="bg-fast-panel rounded-lg shadow-card p-5">
            <h2 className="text-lg font-semibold text-fast-text mb-4">Applicant Information</h2>
            <div className="grid grid-cols-2 gap-4">
              <InfoField label="Full Name"        value={caseData.applicantName || undefined} />
              <InfoField label="NI Number"        value={caseData.niNumber ? maskNI(caseData.niNumber) : undefined} />
              <InfoField label="Date of Birth"    value={caseData.dob ? formatDob(caseData.dob) : undefined} />
              <InfoField label="Email"            value={caseData.applicantEmail || undefined} />
              <InfoField label="Phone"            value={caseData.phone} />
              <InfoField label="Application Type" value={caseData.applicationType || undefined} />
              <InfoField label="Assigned To"      value={caseData.assignedToName || undefined} />
              <InfoField label="Date Submitted"   value={formatDate(caseData.createdAt)} />
            </div>
          </div>

          {/* Documents — viewable per requirements/spec: list with View and Download per document */}
          <div className="bg-fast-panel rounded-lg shadow-card p-5">
            <h2 className="text-lg font-semibold text-fast-text mb-4">Documents</h2>
            <div className="space-y-2">
              {(caseData.documents ?? []).map((doc) => (
                <div key={doc.id} className="flex items-center justify-between p-3 bg-gray-50 rounded-md gap-3">
                  <div className="flex items-center gap-2 min-w-0">
                    <span className="text-fast-muted flex-shrink-0">📄</span>
                    <div className="min-w-0">
                      <span className="text-sm font-medium text-fast-text block truncate">{doc.name}</span>
                      <span className="text-xs text-fast-muted">
                        {doc.type} · {new Date(doc.uploadedAt).toLocaleDateString('en-GB', { day: '2-digit', month: 'short', year: 'numeric' })}
                      </span>
                    </div>
                  </div>
                  <div className="flex items-center gap-2 flex-shrink-0">
                    <span className="text-xs text-fast-approved font-medium bg-fast-green-light px-2 py-0.5 rounded-full">
                      Submitted
                    </span>
                    {doc.viewUrl && (
                      <a
                        href={doc.viewUrl}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-xs font-medium text-fast-teal hover:underline px-2 py-1 rounded border border-fast-teal/40 hover:bg-fast-teal/5"
                      >
                        View
                      </a>
                    )}
                    {doc.downloadUrl && (
                      <a
                        href={doc.downloadUrl}
                        download
                        target="_blank"
                        rel="noopener noreferrer"
                        className="text-xs font-medium text-fast-teal hover:underline px-2 py-1 rounded border border-fast-teal/40 hover:bg-fast-teal/5"
                      >
                        Download
                      </a>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>

          {/* AI Analysis */}
          <div className="bg-fast-panel rounded-lg shadow-card p-5">
            <div className="flex items-center gap-2 mb-4">
              <h2 className="text-lg font-semibold text-fast-text">AI Analysis</h2>
              <span className="text-xs bg-fast-teal-light text-fast-teal px-2 py-0.5 rounded-full font-medium">AI Generated</span>
            </div>
            <div className="space-y-4">
              <div>
                <p className="text-xs font-semibold text-fast-muted uppercase mb-1">Summary</p>
                <p className="text-sm text-fast-text">
                  Applicant {caseData.applicantName} has submitted a {caseData.applicationType} claim.
                  Automated checks have verified submitted documents.{' '}
                  {caseData.aiConfidence !== undefined
                    ? `AI confidence score: ${caseData.aiConfidence}%.`
                    : ''}
                </p>
              </div>
              <div>
                <p className="text-xs font-semibold text-fast-muted uppercase mb-1">Recommendation</p>
                {caseData.aiRecommendation ? (
                  <span className={`inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm font-bold text-white ${
                    caseData.aiRecommendation === 'APPROVE' ? 'bg-fast-approved' : 'bg-fast-declined'
                  }`}>
                    {caseData.aiRecommendation}
                  </span>
                ) : (
                  <span className="text-sm text-fast-muted">Not available</span>
                )}
              </div>
              <div>
                <p className="text-xs font-semibold text-fast-muted uppercase mb-2">Rule Evaluations</p>
                <div className="space-y-2">
                  {[
                    { rule: 'Eligibility Criteria', passed: true },
                    { rule: 'Income Threshold',     passed: (caseData.aiConfidence ?? 0) > 60 },
                    { rule: 'Identity Verified',    passed: caseData.status !== 'ESCALATED' },
                    { rule: 'Documentation Complete', passed: true },
                  ].map((item) => (
                    <div key={item.rule} className="flex items-center justify-between p-2 rounded-md bg-gray-50">
                      <span className="text-sm text-fast-text">{item.rule}</span>
                      <span className={`text-xs font-semibold px-2 py-0.5 rounded-full ${
                        item.passed ? 'bg-fast-green-light text-fast-approved' : 'bg-fast-red-light text-fast-declined'
                      }`}>
                        {item.passed ? 'PASS' : 'FAIL'}
                      </span>
                    </div>
                  ))}
                </div>
              </div>
            </div>
          </div>

          {/* Notes */}
          <div className="bg-fast-panel rounded-lg shadow-card p-5">
            <h2 className="text-lg font-semibold text-fast-text mb-3">Caseworker Notes</h2>
            <textarea
              defaultValue={caseData.notes ?? ''}
              placeholder="Add notes about this case…"
              className="w-full px-3 py-2 border border-gray-200 rounded-md text-sm text-fast-text focus:outline-none focus:ring-2 focus:ring-fast-teal resize-none"
              rows={4}
            />
          </div>

          {/* Audit Trail */}
          <div className="bg-fast-panel rounded-lg shadow-card p-5">
            <h2 className="text-lg font-semibold text-fast-text mb-4">Audit Trail</h2>
            <ol className="relative border-l border-gray-200 ml-2 space-y-4">
              {[
                { label: 'Case Submitted',     date: caseData.createdAt, actor: 'Applicant' },
                { label: 'AI Processing Complete', date: caseData.createdAt, actor: 'System' },
                { label: 'Assigned to Caseworker', date: caseData.createdAt, actor: 'System' },
                ...(isEscalated ? [{ label: 'Escalated for Review', date: caseData.updatedAt, actor: caseData.assignedToName }] : []),
                ...(isDecided   ? [{ label: `Case ${caseData.status}`, date: caseData.updatedAt, actor: caseData.assignedToName }] : []),
              ].map((entry, i) => (
                <li key={i} className="ml-4">
                  <div className="absolute -left-1.5 mt-1 w-3 h-3 rounded-full bg-fast-teal border-2 border-white" />
                  <p className="text-sm font-medium text-fast-text">{entry.label}</p>
                  <p className="text-xs text-fast-muted">{formatDate(entry.date)} — {entry.actor}</p>
                </li>
              ))}
            </ol>
          </div>
        </div>

        {/* Right column */}
        <div className="space-y-6">
          {/* AI Confidence */}
          <div className="bg-fast-panel rounded-lg shadow-card p-5">
            <h2 className="text-lg font-semibold text-fast-text mb-4">AI Confidence</h2>
            <div className="text-center mb-3">
              <p className="text-4xl font-bold" style={{
                color: (caseData.aiConfidence ?? 0) >= 70 ? '#003A46' :
                       (caseData.aiConfidence ?? 0) >= 50 ? '#003A46' : '#f44336'
              }}>
                {caseData.aiConfidence ?? '—'}%
              </p>
            </div>
            <div className="h-3 bg-gray-200 rounded-full overflow-hidden">
              <div
                className="h-full rounded-full"
                style={{
                  width:  `${caseData.aiConfidence ?? 0}%`,
                  backgroundColor:
                    (caseData.aiConfidence ?? 0) >= 70 ? '#003A46' :
                    (caseData.aiConfidence ?? 0) >= 50 ? '#003A46' : '#f44336',
                }}
              />
            </div>
            <p className="text-xs text-fast-muted mt-2 text-center">
              {(caseData.aiConfidence ?? 0) >= 70 ? 'High confidence' :
               (caseData.aiConfidence ?? 0) >= 50 ? 'Moderate confidence' : 'Low confidence — review carefully'}
            </p>
          </div>

          {/* Decision Panel — show when case is actionable, or when escalated and current user is a Manager (manager can approve/decline with suggested email) */}
          {((caseData.status === 'PENDING' || caseData.status === 'IN_PROGRESS') || (caseData.status === 'ESCALATED' && user?.role === 'MANAGER')) && (
            <DecisionPanel caseData={caseData} />
          )}

          {/* If already decided, or escalated but not a Manager, show info panel */}
          {(isDecided || (isEscalated && user?.role !== 'MANAGER')) && (
            <div className="bg-fast-panel rounded-lg shadow-card p-5">
              <h3 className="text-base font-semibold text-fast-text mb-2">No Further Action</h3>
              <p className="text-sm text-fast-muted">
                This case has a final status of{' '}
                <strong>{caseData.status.replace('_', ' ')}</strong>.
                {isEscalated && user?.role !== 'MANAGER' && ' A manager is reviewing this escalation.'}
              </p>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

/** Derive applicant display fields from API + extractedData so details are visible in the portal */
function withApplicantDisplayFields<T extends Record<string, unknown>>(c: T): T {
  const ext = (c.extractedData as Record<string, unknown> | undefined) ?? {};
  const pick = (...keys: string[]): string | undefined => {
    for (const k of keys) {
      const v = ext[k] ?? (c as Record<string, unknown>)[k];
      if (v != null && String(v).trim()) return String(v).trim();
    }
    return undefined;
  };
  return {
    ...c,
    applicantName: (c.applicantName as string)?.trim() || pick('full_name', 'applicant_name', 'name', 'applicantName') || '',
    applicantEmail: (c.applicantEmail as string)?.trim() || pick('email', 'applicant_email', 'applicantEmail') || '',
    niNumber: (c.niNumber as string) || pick('ni_number', 'nino', 'national_insurance_number', 'nationalInsuranceNumber'),
    dob: (c.dob as string) || pick('dob', 'date_of_birth', 'dateOfBirth', 'birth_date'),
    phone: (c.phone as string) || pick('phone', 'phone_number', 'telephone', 'mobile', 'contact_number'),
  } as T;
}

function InfoField({ label, value }: { label: string; value: string | undefined }) {
  return (
    <div>
      <p className="text-xs text-fast-muted mb-0.5">{label}</p>
      <p className="text-sm font-medium text-fast-text">{value ?? '—'}</p>
    </div>
  );
}

function maskNI(ni: string) {
  // Show first 2 and last 2 chars, mask the rest
  const clean = ni.replace(/\s/g, '');
  return clean.slice(0, 2) + '****' + clean.slice(-2);
}

function formatDate(iso: string) {
  return new Date(iso).toLocaleDateString('en-GB', {
    day: '2-digit', month: 'short', year: 'numeric',
  });
}

function formatDob(dob: string) {
  return new Date(dob).toLocaleDateString('en-GB', {
    day: '2-digit', month: 'long', year: 'numeric',
  });
}

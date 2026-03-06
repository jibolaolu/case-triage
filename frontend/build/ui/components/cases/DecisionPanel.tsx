'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { recordDecision } from '@/lib/api/decisions';
import type { Decision, MockCase } from '@/types';

type DecisionPanelProps = {
  caseData: MockCase;
};

const DECISION_CONFIG = {
  approve: {
    label: 'APPROVE',
    icon: '✓',
    btnClass: 'bg-fast-approved hover:bg-fast-teal',
    title: 'Approve Application',
    decisionValue: 'APPROVED' as const,
  },
  decline: {
    label: 'DECLINE',
    icon: '✕',
    btnClass: 'bg-fast-declined hover:bg-red-600',
    title: 'Decline Application',
    decisionValue: 'DECLINED' as const,
  },
  escalate: {
    label: 'ESCALATE',
    icon: '⚠',
    btnClass: 'bg-fast-escalated hover:bg-orange-600',
    title: 'Escalate Application',
    decisionValue: 'ESCALATED' as const,
  },
};

/** AI-suggested reason for the decision, based on case data (caseworker can edit before sending). */
function generateAiSuggestedReason(caseData: MockCase, decision: Decision): string {
  const { applicationType, aiRecommendation, aiConfidence } = caseData;
  const app = applicationType || 'application';
  switch (decision) {
    case 'approve':
      if (aiRecommendation === 'APPROVE' && aiConfidence != null) {
        return `All eligibility criteria have been met for this ${app}. Supporting documents have been verified and the case meets policy requirements (AI confidence: ${aiConfidence}%).`;
      }
      return `Eligibility criteria and supporting documentation for this ${app} have been verified. The application meets the required policy standards.`;
    case 'decline':
      if (aiRecommendation === 'DECLINE' && aiConfidence != null) {
        return `After review, this ${app} does not meet the current eligibility criteria. Supporting information was insufficient to approve (AI confidence: ${aiConfidence}%).`;
      }
      return `This ${app} does not meet the eligibility requirements at this time. The applicant may reapply or request a review if circumstances change.`;
    case 'escalate':
      return `This ${app} requires senior review due to its complexity or edge-case factors. A manager will assess and provide a decision shortly.`;
    default:
      return '';
  }
}

function generateAiEmailDraft(
  caseData: MockCase,
  decision: 'APPROVED' | 'DECLINED' | 'ESCALATED',
  justification: string
) {
  const subjects: Record<string, string> = {
    APPROVED:  `Your Application Has Been Approved – ${caseData.id}`,
    DECLINED:  `Update on Your Application – ${caseData.id}`,
    ESCALATED: `Your Application is Under Further Review – ${caseData.id}`,
  };

  const bodies: Record<string, string> = {
    APPROVED: `Dear ${caseData.applicantName},

We are pleased to inform you that your application (Reference: ${caseData.id}) for ${caseData.applicationType} has been reviewed and approved.

Reason for approval: ${justification}

You will receive further information about the next steps shortly. If you have any questions, please do not hesitate to contact us.

Kind regards,
The FastStart Benefits Processing Team`,

    DECLINED: `Dear ${caseData.applicantName},

Thank you for submitting your application (Reference: ${caseData.id}) for ${caseData.applicationType}.

After careful review, we regret to inform you that your application has not been successful at this time.

Reason for decision: ${justification}

You have the right to appeal this decision within 28 days. Please visit our website or contact our helpline for further information.

Kind regards,
The FastStart Benefits Processing Team`,

    ESCALATED: `Dear ${caseData.applicantName},

We are writing regarding your application (Reference: ${caseData.id}) for ${caseData.applicationType}.

Your application requires additional review by a senior caseworker. This is to ensure your case receives the attention it deserves.

Reason for escalation: ${justification}

We aim to provide you with a decision within 5 working days. You do not need to take any action at this time.

Kind regards,
The FastStart Benefits Processing Team`,
  };

  return {
    subject: subjects[decision],
    body: bodies[decision],
  };
}

type ModalStep = 'justification' | 'email_review';

export function DecisionPanel({ caseData }: DecisionPanelProps) {
  const router = useRouter();
  const [decision, setDecision] = useState<Decision | null>(null);
  const [justification, setJustification] = useState('');
  const [confirmed, setConfirmed] = useState(false);
  const [loading, setLoading] = useState(false);
  const [showModal, setShowModal] = useState(false);
  const [step, setStep] = useState<ModalStep>('justification');
  const [emailDraft, setEmailDraft] = useState<{ subject: string; body: string } | null>(null);
  const [editingEmail, setEditingEmail] = useState(false);
  const [editedSubject, setEditedSubject] = useState('');
  const [editedBody, setEditedBody] = useState('');
  const [sending, setSending] = useState(false);

  const openModal = (d: Decision) => {
    setDecision(d);
    setJustification(generateAiSuggestedReason(caseData, d));
    setConfirmed(false);
    setEmailDraft(null);
    setStep('justification');
    setShowModal(true);
  };

  const handleReviewEmail = () => {
    if (!decision || justification.trim().length < 10 || !confirmed) return;
    setLoading(true);
    const config = DECISION_CONFIG[decision];
    const draft = generateAiEmailDraft(caseData, config.decisionValue, justification.trim());
    setEmailDraft(draft);
    setEditedSubject(draft.subject);
    setEditedBody(draft.body);
    setEditingEmail(false);
    setLoading(false);
    setStep('email_review');
  };

  const handleSendEmail = async () => {
    if (!decision || !emailDraft) return;
    const subjectToSend = editingEmail ? editedSubject : emailDraft.subject;
    const bodyToSend = editingEmail ? editedBody : emailDraft.body;
    setSending(true);
    try {
      await recordDecision(caseData.id, {
        decision,
        justification: justification.trim(),
      });
      // Simulate email send (API may handle this separately in future)
      await new Promise((r) => setTimeout(r, 400));
    } catch (err) {
      console.error('Failed to record decision:', err);
      setSending(false);
      alert('Failed to record decision. Please try again.');
      return;
    }
    setSending(false);
    setShowModal(false);
    router.push('/cases');
  };

  const handleCancelEmail = () => {
    setShowModal(false);
    setStep('justification');
    setEmailDraft(null);
  };

  const isReady = justification.trim().length >= 10 && confirmed && !loading;

  return (
    <>
      <div className="bg-fast-panel rounded-lg shadow-card p-5">
        <h3 className="text-lg font-semibold text-fast-text mb-1">Decision Actions</h3>
        <p className="text-xs text-fast-muted mb-4">
          Click Approve, Decline, or Escalate to open a pop-up with the AI-suggested email. You can send the email only from that pop-up.
        </p>
        <div className="space-y-2">
          {(['approve', 'decline', 'escalate'] as Decision[]).map((d) => {
            const cfg = DECISION_CONFIG[d];
            return (
              <button
                key={d}
                onClick={() => openModal(d)}
                className={`w-full flex items-center justify-center gap-2 px-4 py-3 ${cfg.btnClass} text-white rounded-md font-semibold transition-colors`}
              >
                <span>{cfg.icon}</span>
                {cfg.label}
              </button>
            );
          })}
        </div>
      </div>

      {/* Decision + email review modal (pop-up with AI-suggested email) */}
      {showModal && decision && (
        <div className="fixed inset-0 bg-black/50 flex items-center justify-center z-50 p-4">
          <div className="bg-fast-panel rounded-lg shadow-xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
            <div className="p-6">
              {step === 'justification' ? (
                <>
                  <div className="flex items-center justify-between mb-4">
                    <div>
                      <h2 className="text-xl font-bold text-fast-teal">
                        {DECISION_CONFIG[decision].icon} {DECISION_CONFIG[decision].title}
                      </h2>
                      <p className="text-sm text-fast-muted mt-0.5">Case: {caseData.id}</p>
                    </div>
                    <button
                      onClick={handleCancelEmail}
                      className="text-fast-muted hover:text-fast-text text-2xl leading-none"
                    >
                      ×
                    </button>
                  </div>

                  <div className="bg-yellow-50 border border-yellow-200 rounded-lg p-3 mb-4">
                    <p className="text-sm text-yellow-800">
                      <strong>Note:</strong> You will see the AI-suggested email in the next step. The case status will only update when you send the email.
                    </p>
                  </div>

                  {caseData.aiRecommendation && (
                    <div className="mb-4 bg-fast-blue-light rounded-lg p-3">
                      <p className="text-xs font-semibold text-fast-text mb-1">AI Recommendation</p>
                      <div className="flex items-center gap-2">
                        <span className={`px-3 py-0.5 rounded-full text-xs font-bold text-white ${
                          caseData.aiRecommendation === 'APPROVE' ? 'bg-fast-approved' : 'bg-fast-declined'
                        }`}>
                          {caseData.aiRecommendation}
                        </span>
                        <span className="text-xs text-fast-muted">{caseData.aiConfidence}% Confidence</span>
                      </div>
                    </div>
                  )}

                  <div className="mb-4">
                    <label className="block text-sm font-semibold text-fast-text mb-1">
                      {decision === 'approve' ? 'Approval Reason' : decision === 'decline' ? 'Decline Reason' : 'Escalation Reason'}
                      <span className="text-fast-declined ml-1">*</span>
                      <span className="ml-1 text-xs font-normal text-fast-muted">(AI-suggested; you can edit)</span>
                    </label>
                    <textarea
                      value={justification}
                      onChange={(e) => setJustification(e.target.value)}
                      className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm focus:outline-none focus:ring-2 focus:ring-fast-teal resize-none"
                      rows={4}
                      placeholder="Enter a reason (minimum 10 characters)…"
                    />
                    <p className={`text-xs mt-1 ${justification.trim().length < 10 && justification.length > 0 ? 'text-fast-declined' : 'text-fast-muted'}`}>
                      {justification.length} characters {justification.trim().length < 10 ? '(minimum 10 required)' : ''}
                    </p>
                  </div>

                  <div className="mb-6">
                    <label className="flex items-start gap-2 cursor-pointer">
                      <input
                        type="checkbox"
                        checked={confirmed}
                        onChange={(e) => setConfirmed(e.target.checked)}
                        className="mt-0.5 rounded border-gray-300 text-fast-teal focus:ring-fast-teal"
                      />
                      <span className="text-sm text-fast-text">
                        I confirm I have reviewed all information and wish to{' '}
                        <strong>{decision}</strong> this application.
                      </span>
                    </label>
                  </div>

                  <div className="flex gap-3">
                    <button
                      onClick={handleCancelEmail}
                      className="flex-1 px-4 py-2 text-fast-text hover:bg-gray-100 rounded-md font-medium transition-colors border border-gray-200"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleReviewEmail}
                      disabled={!isReady}
                      className={`flex-1 px-4 py-2 rounded-md font-semibold text-white transition-colors disabled:opacity-40 ${
                        DECISION_CONFIG[decision].btnClass
                      }`}
                    >
                      {loading ? 'Preparing…' : 'Review AI-suggested email'}
                    </button>
                  </div>
                </>
              ) : (
                <>
                  <div className="flex items-center justify-between mb-4">
                    <h2 className="text-xl font-bold text-fast-teal">AI-suggested email</h2>
                    <div className="flex items-center gap-2">
                      {emailDraft && (
                        <button
                          type="button"
                          onClick={() => setEditingEmail((e) => !e)}
                          className="px-3 py-1.5 text-sm font-medium border border-fast-teal text-fast-teal rounded-md hover:bg-fast-teal hover:text-white transition-colors"
                        >
                          {editingEmail ? 'Done editing' : 'Edit'}
                        </button>
                      )}
                      <button
                        onClick={() => { setStep('justification'); setEmailDraft(null); setEditingEmail(false); }}
                        className="text-fast-muted hover:text-fast-text text-sm"
                      >
                        ← Back
                      </button>
                    </div>
                  </div>

                  <p className="text-sm text-fast-muted mb-3">
                    {editingEmail
                      ? 'Edit the subject and body as needed, then click &quot;Send Email&quot; or Cancel.'
                      : 'Review the email below. Click &quot;Edit&quot; to add or change the draft, then &quot;Send Email&quot; to send and update the case.'}
                  </p>

                  {emailDraft && (
                    <div className="space-y-4 mb-6 border border-gray-200 rounded-lg p-4 bg-gray-50">
                      <div>
                        <p className="text-xs font-semibold text-fast-muted uppercase mb-1">To</p>
                        <p className="text-sm text-fast-text">{caseData.applicantName} &lt;{caseData.applicantEmail}&gt;</p>
                      </div>
                      <div>
                        <p className="text-xs font-semibold text-fast-muted uppercase mb-1">Subject</p>
                        {editingEmail ? (
                          <input
                            type="text"
                            value={editedSubject}
                            onChange={(e) => setEditedSubject(e.target.value)}
                            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm text-fast-text focus:outline-none focus:ring-2 focus:ring-fast-teal"
                          />
                        ) : (
                          <p className="text-sm text-fast-text">{emailDraft.subject}</p>
                        )}
                      </div>
                      <div>
                        <p className="text-xs font-semibold text-fast-muted uppercase mb-1">Body</p>
                        {editingEmail ? (
                          <textarea
                            value={editedBody}
                            onChange={(e) => setEditedBody(e.target.value)}
                            rows={12}
                            className="w-full px-3 py-2 border border-gray-300 rounded-md text-sm text-fast-text font-sans focus:outline-none focus:ring-2 focus:ring-fast-teal resize-y"
                          />
                        ) : (
                          <pre className="text-sm text-fast-text whitespace-pre-wrap font-sans max-h-48 overflow-y-auto">{emailDraft.body}</pre>
                        )}
                      </div>
                    </div>
                  )}

                  <div className="flex gap-3">
                    <button
                      onClick={handleCancelEmail}
                      className="flex-1 px-4 py-2 text-fast-text hover:bg-gray-100 rounded-md font-medium transition-colors border border-gray-200"
                    >
                      Cancel
                    </button>
                    <button
                      onClick={handleSendEmail}
                      disabled={sending}
                      className={`flex-1 px-4 py-2 rounded-md font-semibold text-white transition-colors disabled:opacity-40 ${
                        DECISION_CONFIG[decision].btnClass
                      }`}
                    >
                      {sending ? 'Sending…' : 'Send Email'}
                    </button>
                  </div>
                </>
              )}
            </div>
          </div>
        </div>
      )}
    </>
  );
}

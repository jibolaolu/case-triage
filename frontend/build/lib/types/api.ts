/**
 * Shared API types – aligned with build/api/contracts/openapi.yaml.
 * Can be consumed by build/ui and other TypeScript services.
 */

export type CaseStatus =
  | 'intake'
  | 'processing'
  | 'ready_for_review'
  | 'in_review'
  | 'approved'
  | 'declined'
  | 'escalated';

export type CaseSummary = {
  caseId: string;
  organisationId: string;
  caseTypeId: string;
  status: CaseStatus;
  priority?: number;
  createdAt: string;
  updatedAt: string;
};

export type CaseDetail = CaseSummary & {
  applicantSummary?: string;
  documents?: { documentId: string; name: string; type?: string }[];
  extractedData?: Record<string, unknown>;
  recommendation?: string;
  ruleEvaluations?: { ruleId: string; passed: boolean; reason?: string }[];
};

export type Decision = 'approve' | 'decline' | 'escalate';

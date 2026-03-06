/**
 * Decisions API – record decision for a case. Align with OpenAPI POST /api/cases/{id}/decision.
 */

import { apiClient } from './client';

export type RecordDecisionBody = {
  decision: 'approve' | 'decline' | 'escalate';
  justification: string;
  idempotencyKey?: string;
};

export async function recordDecision(
  caseId: string,
  body: RecordDecisionBody
): Promise<{ success: boolean }> {
  const { data } = await apiClient.post<{ success: boolean }>(
    `/cases/${caseId}/decision`,
    body
  );
  return data;
}

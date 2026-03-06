/**
 * Cases API – list and get case detail. Align with OpenAPI /api/cases.
 */

import { apiClient } from './client';
import type { CaseSummary, CaseDetail } from '@/types';

export async function getCases(params?: {
  status?: string;
  limit?: number;
  nextToken?: string;
}): Promise<{ cases: CaseSummary[]; nextToken?: string }> {
  const { data } = await apiClient.get<{ cases: CaseSummary[]; nextToken?: string }>('/cases', {
    params,
  });
  return data;
}

export async function getCaseDetail(caseId: string): Promise<CaseDetail> {
  const { data } = await apiClient.get<CaseDetail>(`/cases/${caseId}`);
  return data;
}

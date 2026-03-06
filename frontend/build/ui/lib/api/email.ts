import { apiClient } from './client';

export async function sendDecisionEmail(caseId: string, body: {
  subject: string;
  body: string;
  toAddress: string;
  toName: string;
  decision: string;
}): Promise<{ message: string }> {
  const { data } = await apiClient.post<{ message: string }>(`/cases/${caseId}/email`, body);
  return data;
}

import { apiClient } from './client';
import type { Policy } from '@/types';

export async function getPolicies(): Promise<{ policies: Policy[] }> {
  const { data } = await apiClient.get<{ policies: Policy[] }>('/admin/policies');
  return data;
}

export async function getPolicy(policyId: string): Promise<Policy> {
  const { data } = await apiClient.get<Policy>(`/admin/policies/${policyId}`);
  return data;
}

export async function createPolicy(body: { name: string; category: string; content?: string }): Promise<Policy> {
  const { data } = await apiClient.post<Policy>('/admin/policies', body);
  return data;
}

export async function updatePolicy(policyId: string, body: { name?: string; category?: string }): Promise<Policy> {
  const { data } = await apiClient.put<Policy>(`/admin/policies/${policyId}`, body);
  return data;
}

export async function deletePolicy(policyId: string): Promise<void> {
  await apiClient.delete(`/admin/policies/${policyId}`);
}

import { apiClient } from './client';
import type { MockUser } from '@/types';

export async function getUsers(): Promise<{ users: MockUser[] }> {
  const { data } = await apiClient.get<{ users: MockUser[] }>('/admin/users');
  return data;
}

export async function createUser(body: { name: string; email: string; role: string; department: string }): Promise<{ user: MockUser }> {
  const { data } = await apiClient.post<{ user: MockUser }>('/admin/users', body);
  return data;
}

export async function updateUserRole(userId: string, role: string): Promise<void> {
  await apiClient.put(`/admin/users/${userId}/role`, { role });
}

/** Spec: body is { active: boolean }. We map ACTIVE/INACTIVE for the UI. */
export async function updateUserStatus(userId: string, status: 'ACTIVE' | 'INACTIVE'): Promise<void> {
  await apiClient.put(`/admin/users/${userId}/status`, { active: status === 'ACTIVE' });
}

export async function deleteUser(userId: string): Promise<void> {
  await apiClient.delete(`/admin/users/${userId}`);
}

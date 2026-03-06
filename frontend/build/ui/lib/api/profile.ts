import { apiClient } from './client';
import type { UserProfile } from '@/types';

export async function getUserProfile(): Promise<UserProfile> {
  const { data } = await apiClient.get<UserProfile>('/users/me');
  return data;
}

export async function updateUserProfile(body: Partial<UserProfile>): Promise<UserProfile> {
  const { data } = await apiClient.put<UserProfile>('/users/me', body);
  return data;
}

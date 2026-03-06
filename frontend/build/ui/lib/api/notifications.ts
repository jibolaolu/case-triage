import { apiClient } from './client';
import type { Notification } from '@/types';

export async function getNotifications(params?: { unreadOnly?: boolean }): Promise<{ notifications: Notification[] }> {
  const { data } = await apiClient.get<{ notifications: Notification[] }>('/notifications', { params });
  return data;
}

export async function markNotificationRead(notificationId: string): Promise<void> {
  await apiClient.put(`/notifications/${notificationId}/read`);
}

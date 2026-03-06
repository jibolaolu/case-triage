'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getNotifications, markNotificationRead } from '@/lib/api/notifications';

export function useNotifications(params?: { unreadOnly?: boolean }) {
  return useQuery({
    queryKey: ['notifications', params],
    queryFn: () => getNotifications(params),
  });
}

export function useMarkNotificationRead() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (notificationId: string) => markNotificationRead(notificationId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['notifications'] });
    },
  });
}

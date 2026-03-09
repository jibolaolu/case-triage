'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import { getUserProfile, updateUserProfile } from '@/lib/api/profile';
import type { UserProfile } from '@/types';

export function useUserProfile() {
  return useQuery({
    queryKey: ['user', 'profile'],
    queryFn: () => getUserProfile(),
  });
}

export function useUpdateUserProfile() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (body: Partial<UserProfile>) => updateUserProfile(body),
    onSuccess: (data) => {
      queryClient.setQueryData(['user', 'profile'], data);
    },
  });
}

'use client';

import { useQuery } from '@tanstack/react-query';
import { getCases } from '@/lib/api';

export function useCases(params?: { status?: string; limit?: number }) {
  return useQuery({
    queryKey: ['cases', params],
    queryFn: () => getCases(params),
  });
}

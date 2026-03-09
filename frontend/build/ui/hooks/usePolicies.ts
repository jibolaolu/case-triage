'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getPolicies,
  getPolicy,
  createPolicy,
  updatePolicy,
  deletePolicy,
} from '@/lib/api/policies';
import type { Policy } from '@/types';

export function usePolicies() {
  return useQuery({
    queryKey: ['admin', 'policies'],
    queryFn: () => getPolicies(),
  });
}

export function usePolicy(policyId: string | null) {
  return useQuery({
    queryKey: ['admin', 'policies', policyId],
    queryFn: () => getPolicy(policyId!),
    enabled: !!policyId,
  });
}

export function useCreatePolicy() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (body: { orgId?: string; caseType?: string; name?: string; category?: string }) =>
      createPolicy({
        name: body.name ?? '',
        category: body.category ?? '',
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'policies'] });
    },
  });
}

export function useUpdatePolicy() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({
      policyId,
      body,
    }: {
      policyId: string;
      body: { status?: string; effectiveDate?: string; retiredDate?: string; name?: string; category?: string };
    }) => updatePolicy(policyId, body),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'policies'] });
    },
  });
}

export function useDeletePolicy() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (policyId: string) => deletePolicy(policyId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'policies'] });
    },
  });
}

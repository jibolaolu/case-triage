'use client';

import { useQuery } from '@tanstack/react-query';
import { getCaseDetail } from '@/lib/api';

export function useCaseDetail(caseId: string | null) {
  return useQuery({
    queryKey: ['case', caseId],
    queryFn: () => getCaseDetail(caseId!),
    enabled: !!caseId,
  });
}

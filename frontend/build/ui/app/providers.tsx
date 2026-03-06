'use client';

import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { AuthProvider } from '@/contexts/AuthContext';
import { EmailDraftProvider } from '@/contexts/EmailDraftContext';

const queryClient = new QueryClient({
  defaultOptions: {
    queries: {
      staleTime: 30000,
      retry: 2,
    },
  },
});

export function Providers({ children }: { children: React.ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>
      <AuthProvider>
        <EmailDraftProvider>
          {children}
        </EmailDraftProvider>
      </AuthProvider>
    </QueryClientProvider>
  );
}

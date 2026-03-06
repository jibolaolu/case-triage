'use client';

import {
  createContext,
  useContext,
  useState,
  type ReactNode,
} from 'react';
import type { EmailDraft } from '@/types';

type EmailDraftContextValue = {
  draft: EmailDraft | null;
  setDraft: (draft: EmailDraft | null) => void;
};

const EmailDraftContext = createContext<EmailDraftContextValue | null>(null);

export function EmailDraftProvider({ children }: { children: ReactNode }) {
  const [draft, setDraft] = useState<EmailDraft | null>(null);

  return (
    <EmailDraftContext.Provider value={{ draft, setDraft }}>
      {children}
    </EmailDraftContext.Provider>
  );
}

export function useEmailDraft() {
  const ctx = useContext(EmailDraftContext);
  if (!ctx) throw new Error('useEmailDraft must be used within EmailDraftProvider');
  return ctx;
}

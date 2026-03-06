import type { Metadata } from 'next';
import '@/styles/globals.css';
import { Providers } from './providers';

export const metadata: Metadata = {
  title: 'FastStart – Caseworker Portal',
  description: 'AI-powered case triage and caseworker portal',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" className="light">
      <body className="antialiased bg-fast-bg text-fast-text">
        <Providers>{children}</Providers>
      </body>
    </html>
  );
}

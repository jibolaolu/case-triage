'use client';

import { cn } from '@/lib/utils';

type InputProps = React.InputHTMLAttributes<HTMLInputElement>;

export function Input({ className, ...props }: InputProps) {
  return (
    <input
      className={cn(
        'block w-full rounded-md border border-gray-300 px-3 py-2 text-sm shadow-sm focus:border-fast-teal focus:outline-none focus:ring-1 focus:ring-fast-teal',
        className
      )}
      {...props}
    />
  );
}

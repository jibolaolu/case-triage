'use client';

import { cn } from '@/lib/utils';

type ButtonProps = React.ButtonHTMLAttributes<HTMLButtonElement> & {
  variant?: 'primary' | 'secondary' | 'danger' | 'success' | 'warning';
  size?: 'sm' | 'md' | 'lg';
};

/**
 * Button component – matches requirement screenshots.
 * Primary and success: single teal #003A46 only. Danger: red, Warning: orange.
 */
export function Button({
  className,
  variant = 'primary',
  size = 'md',
  children,
  ...props
}: ButtonProps) {
  const base = 'inline-flex items-center justify-center rounded-md font-medium focus:outline-none focus:ring-2 focus:ring-offset-2 disabled:opacity-50 transition-colors';
  const variants = {
    primary: 'bg-fast-teal text-white hover:opacity-90 focus:ring-fast-teal',
    secondary: 'bg-gray-200 text-fast-text hover:bg-gray-300 focus:ring-gray-500',
    danger: 'bg-fast-declined text-white hover:bg-red-600 focus:ring-red-500',
    success: 'bg-fast-approved text-white hover:bg-fast-teal focus:ring-fast-teal',
    warning: 'bg-fast-escalated text-white hover:bg-orange-600 focus:ring-orange-500',
  };
  const sizes = {
    sm: 'px-3 py-1.5 text-sm',
    md: 'px-4 py-2 text-sm',
    lg: 'px-6 py-3 text-base',
  };
  return (
    <button
      className={cn(base, variants[variant], sizes[size], className)}
      {...props}
    >
      {children}
    </button>
  );
}

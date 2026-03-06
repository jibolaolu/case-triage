'use client';

import { cn } from '@/lib/utils';

type StatusChipProps = {
  status: string;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
};

/**
 * Status Chip – matches requirement screenshot styling.
 * Pill-shaped tags with appropriate colors for status values.
 */
export function StatusChip({ status, size = 'md', className }: StatusChipProps) {
  const normalized = status.toUpperCase().replace(/_/g, ' ');
  
  const getStatusStyles = () => {
    if (normalized.includes('APPROVED')) {
      return 'bg-fast-green-light text-fast-approved';
    }
    if (normalized.includes('DECLINED')) {
      return 'bg-fast-red-light text-fast-declined';
    }
    if (normalized.includes('PENDING') || normalized.includes('REVIEW')) {
      return 'bg-yellow-100 text-yellow-800';
    }
    if (normalized.includes('ESCALATED')) {
      return 'bg-fast-orange-light text-fast-escalated';
    }
    if (normalized.includes('URGENT')) {
      return 'bg-fast-declined text-white';
    }
    if (normalized.includes('HIGH')) {
      return 'bg-fast-orange-light text-fast-high';
    }
    if (normalized.includes('STANDARD')) {
      return 'bg-gray-100 text-fast-standard';
    }
    if (normalized.includes('LOW')) {
      return 'bg-gray-100 text-fast-low';
    }
    return 'bg-gray-100 text-fast-muted';
  };

  const sizes = {
    sm: 'px-2 py-0.5 text-xs',
    md: 'px-3 py-1 text-xs',
    lg: 'px-4 py-1.5 text-sm',
  };

  return (
    <span
      className={cn(
        'inline-block rounded-full font-semibold',
        getStatusStyles(),
        sizes[size],
        className
      )}
    >
      {normalized}
    </span>
  );
}

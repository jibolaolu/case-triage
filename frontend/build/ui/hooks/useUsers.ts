'use client';

import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query';
import {
  getUsers,
  createUser,
  updateUserRole,
  updateUserStatus,
  deleteUser,
} from '@/lib/api/users';
import type { MockUser, UserRole } from '@/types';

/** Map API role (lowercase) to UI UserRole (uppercase). */
function toUserRole(r: string): UserRole {
  const u = (r || '').toUpperCase();
  if (u === 'ADMIN' || u === 'MANAGER' || u === 'CASEWORKER') return u as UserRole;
  return 'CASEWORKER';
}

/** Map API user shape to MockUser (id, name, email, role, status, department, etc.). */
function mapApiUser(u: Record<string, unknown>): MockUser {
  return {
    id: String(u.id ?? u.sub ?? ''),
    name: String(u.name ?? ''),
    email: String(u.email ?? ''),
    role: toUserRole(String(u.role ?? 'caseworker')),
    status: (u.status === 'ENABLED' || u.status === 'ACTIVE' ? 'ACTIVE' : 'INACTIVE') as 'ACTIVE' | 'INACTIVE',
    department: String(u.department ?? ''),
    casesAssigned: Number(u.casesAssigned ?? 0),
    lastLogin: String(u.lastLogin ?? u.lastLoginAt ?? ''),
    createdAt: String(u.createdAt ?? ''),
  };
}

export function useUsers() {
  return useQuery({
    queryKey: ['admin', 'users'],
    queryFn: async () => {
      const res = await getUsers();
      return {
        users: (res.users || []).map((u) => mapApiUser(u as Record<string, unknown>)),
      };
    },
  });
}

export function useCreateUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (body: { name: string; email: string; role: string; department?: string }) =>
      createUser({
        name: body.name,
        email: body.email,
        role: body.role?.toLowerCase() ?? 'caseworker',
        department: body.department ?? '',
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'users'] });
    },
  });
}

export function useUpdateUserRole() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ userId, role }: { userId: string; role: string }) =>
      updateUserRole(userId, role.toLowerCase()),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'users'] });
    },
  });
}

export function useUpdateUserStatus() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: ({ userId, status }: { userId: string; status: 'ACTIVE' | 'INACTIVE' }) =>
      updateUserStatus(userId, status),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'users'] });
    },
  });
}

export function useDeleteUser() {
  const queryClient = useQueryClient();
  return useMutation({
    mutationFn: (userId: string) => deleteUser(userId),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['admin', 'users'] });
    },
  });
}

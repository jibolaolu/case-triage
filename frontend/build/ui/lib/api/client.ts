/**
 * API client – base URL and axios instance.
 * Set NEXT_PUBLIC_API_URL in env (e.g. API Gateway URL).
 */

import axios, { type AxiosInstance } from 'axios';
import { getAccessToken } from '@/lib/auth/session';

const baseURL =
  typeof window !== 'undefined'
    ? (process.env.NEXT_PUBLIC_API_URL || '/api')
    : process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001';

export const apiClient: AxiosInstance = axios.create({
  baseURL,
  timeout: 15000,
  headers: { 'Content-Type': 'application/json' },
});

apiClient.interceptors.request.use((config) => {
  const token = getAccessToken();
  if (token) config.headers.Authorization = `Bearer ${token}`;
  return config;
});

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

apiClient.interceptors.response.use(
  (r) => r,
  (err) => {
    const status = err.response?.status;
    const body = err.response?.data;
    const msg =
      status === 401
        ? 'Unauthorized (401). Sign in with Cognito to load cases from the server.'
        : status === 403
          ? 'Forbidden (403). Check your permissions.'
          : typeof body === 'object' && body?.error
            ? String(body.error)
            : err.message;
    err.message = msg;
    return Promise.reject(err);
  }
);

/**
 * Aurora PostgreSQL client for agents. Uses DB_PROXY_ENDPOINT and DB_SECRET_ARN.
 */

import { SecretsManagerClient, GetSecretValueCommand } from '@aws-sdk/client-secrets-manager';
import pg from 'pg';

const { Pool } = pg;
const secrets = new SecretsManagerClient({});
let pool = null;

function parseEndpoint(endpoint) {
  if (!endpoint) return { host: null, port: 5432 };
  const [host, port] = endpoint.split(':');
  return { host: host || endpoint, port: port ? parseInt(port, 10) : 5432 };
}

export async function getPool() {
  if (pool) return pool;
  const secretArn = process.env.DB_SECRET_ARN;
  const proxyEndpoint = process.env.DB_PROXY_ENDPOINT;
  if (!secretArn || !proxyEndpoint) throw new Error('DB_SECRET_ARN and DB_PROXY_ENDPOINT required');
  const { SecretString } = await secrets.send(new GetSecretValueCommand({ SecretId: secretArn }));
  const creds = JSON.parse(SecretString);
  const { host, port } = parseEndpoint(proxyEndpoint);
  pool = new Pool({
    host: host || proxyEndpoint,
    port,
    database: creds.dbname || creds.database,
    user: creds.username,
    password: creds.password,
    ssl: { rejectUnauthorized: true },
    max: 2,
    idleTimeoutMillis: 30000,
  });
  return pool;
}

export async function query(text, params) {
  const p = await getPool();
  return p.query(text, params);
}

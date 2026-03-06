/**
 * Idempotency: check DynamoDB for existing response by idempotency key; store response after successful processing.
 * TTL 24 hours. Use conditional put to avoid duplicate processing.
 */

import { DynamoDBClient, GetItemCommand, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { marshall, unmarshall } from '@aws-sdk/util-dynamodb';

const client = new DynamoDBClient({});

export async function getIdempotencyResponse(tableName, idempotencyKey) {
  const { Item } = await client.send(new GetItemCommand({
    TableName: tableName,
    Key: marshall({ idempotency_key: idempotencyKey }),
  }));
  if (!Item) return null;
  const row = unmarshall(Item);
  return { statusCode: row.status_code, body: row.response_body };
}

export async function setIdempotencyResponse(tableName, idempotencyKey, statusCode, responseBody, ttlHours = 24) {
  const ttl = Math.floor(Date.now() / 1000) + ttlHours * 3600;
  await client.send(new PutItemCommand({
    TableName: tableName,
    Item: marshall({
      idempotency_key: idempotencyKey,
      status_code: statusCode,
      response_body: typeof responseBody === 'string' ? responseBody : JSON.stringify(responseBody),
      created_at: new Date().toISOString(),
      ttl,
    }, { removeUndefinedValues: true }),
    ConditionExpression: 'attribute_not_exists(idempotency_key)',
  }));
}

export function requireIdempotencyKey(headers) {
  const key = headers?.['idempotency-key'] ?? headers?.['Idempotency-Key'];
  if (!key) {
    const err = new Error('Idempotency-Key header is required for this request');
    err.statusCode = 400;
    throw err;
  }
  return key;
}

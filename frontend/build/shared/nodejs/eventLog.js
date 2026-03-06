/**
 * Persist events to DynamoDB event_log for replay and audit.
 * Attributes: event_id, event_type, case_id, payload, timestamp, ttl (optional).
 */
import { DynamoDBClient, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { marshall } from '@aws-sdk/util-dynamodb';

const dynamo = new DynamoDBClient({});

export async function putEvent(eventType, caseId, payload) {
  const table = process.env.EVENT_LOG_TABLE;
  if (!table) return;
  const now = new Date().toISOString();
  const eventId = `evt-${eventType}-${caseId}-${Date.now()}-${Math.random().toString(36).slice(2, 10)}`;
  const ttl = Math.floor(Date.now() / 1000) + 90 * 24 * 3600; // 90 days
  await dynamo.send(new PutItemCommand({
    TableName: table,
    Item: marshall({
      event_id: eventId,
      event_type: eventType,
      case_id: caseId,
      payload: typeof payload === 'string' ? payload : JSON.stringify(payload),
      timestamp: now,
      ttl,
    }),
  }));
}

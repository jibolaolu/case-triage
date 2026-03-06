/**
 * Step Functions Catch: update case status to AI_PROCESSING_FAILED, emit CASE_AI_FAILED, persist to event_log.
 * Input: { caseId, orgId, failedState, error: { Error, Cause } } (passed dynamically from state machine).
 */
import { DynamoDBClient, UpdateItemCommand, PutItemCommand } from '@aws-sdk/client-dynamodb';
import { EventBridgeClient, PutEventsCommand } from '@aws-sdk/client-eventbridge';
import { marshall } from '@aws-sdk/util-dynamodb';

async function putAIAgentFailures() {
  const emf = {
    _aws: {
      Timestamp: Date.now(),
      CloudWatchMetrics: [{
        Namespace: 'FastStart',
        Dimensions: [['Environment']],
        Metrics: [{ Name: 'AIAgentFailures', Unit: 'Count' }],
      }],
    },
    Environment: process.env.ENVIRONMENT || 'env',
    AIAgentFailures: 1,
  };
  console.log(JSON.stringify(emf));
}

const dynamo = new DynamoDBClient({});
const eventBridge = new EventBridgeClient({});
const TABLE = process.env.CASE_STATE_TABLE;
const EVENT_LOG_TABLE = process.env.EVENT_LOG_TABLE;
const EVENT_BUS_NAME = process.env.EVENT_BUS_NAME || 'default';

export async function handler(event) {
  const caseId = event.detail?.caseId ?? event.caseId;
  const orgId = event.detail?.orgId ?? event.orgId;
  const failedState = event.failedState ?? event.stage ?? 'Unknown';
  const err = event.error ?? { Error: 'Unknown', Cause: '' };
  const errorName = err.Error ?? 'FAILED';
  const errorCause = err.Cause ?? '';

  if (!caseId || !orgId) {
    console.error(JSON.stringify({ message: 'Missing caseId or orgId', event }));
    return { statusCode: 400 };
  }

  await dynamo.send(new UpdateItemCommand({
    TableName: TABLE,
    Key: marshall({ case_id: caseId }),
    UpdateExpression: 'SET #status = :status, updated_at = :now',
    ExpressionAttributeNames: { '#status': 'status' },
    ExpressionAttributeValues: marshall({
      ':status': 'AI_PROCESSING_FAILED',
      ':now': new Date().toISOString(),
    }),
  }));

  const failedDetail = {
    schemaVersion: '1.0',
    caseId,
    orgId,
    failedState,
    errorCode: errorName,
    errorMessage: errorCause,
    failedAt: new Date().toISOString(),
  };
  await eventBridge.send(new PutEventsCommand({
    Entries: [{ Source: 'case.ai', DetailType: 'CASE_AI_FAILED', Detail: JSON.stringify(failedDetail) }],
  }));

  if (EVENT_LOG_TABLE) {
    const now = new Date().toISOString();
    await dynamo.send(new PutItemCommand({
      TableName: EVENT_LOG_TABLE,
      Item: marshall({
        event_id: `evt-CASE_AI_FAILED-${caseId}-${Date.now()}`,
        event_type: 'CASE_AI_FAILED',
        case_id: caseId,
        payload: JSON.stringify(failedDetail),
        timestamp: now,
        ttl: Math.floor(Date.now() / 1000) + 90 * 24 * 3600,
      }),
    }));
  }

  await putAIAgentFailures();
  console.log(JSON.stringify({ message: 'CASE_AI_FAILED emitted', caseId, orgId, failedState }));
  return { statusCode: 200 };
}

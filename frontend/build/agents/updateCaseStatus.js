/**
 * Step Functions: MarkReadyForReview – set case status to READY_FOR_CASEWORKER_REVIEW in DynamoDB and Aurora.
 */
import { DynamoDBClient, UpdateItemCommand } from '@aws-sdk/client-dynamodb';
import { marshall } from '@aws-sdk/util-dynamodb';
import { query } from './db.js';

const dynamo = new DynamoDBClient({});
const TABLE = process.env.CASE_STATE_TABLE;

export async function handler(event) {
  const caseId = event.detail?.caseId ?? event.caseId;
  const orgId = event.detail?.orgId ?? event.orgId;
  if (!caseId) return { statusCode: 400 };

  const now = new Date().toISOString();

  await dynamo.send(new UpdateItemCommand({
    TableName: TABLE,
    Key: marshall({ case_id: caseId }),
    UpdateExpression: 'SET #status = :status, updated_at = :now',
    ExpressionAttributeNames: { '#status': 'status' },
    ExpressionAttributeValues: marshall({
      ':status': 'READY_FOR_CASEWORKER_REVIEW',
      ':now': now,
    }),
  }));

  await query(
    `UPDATE cases SET status = $1, ai_completed_at = $2::timestamptz, updated_at = $2::timestamptz WHERE case_id = $3`,
    ['READY_FOR_CASEWORKER_REVIEW', now, caseId]
  );

  console.log(JSON.stringify({ message: 'Case ready for review', caseId, orgId }));
  return { statusCode: 200 };
}

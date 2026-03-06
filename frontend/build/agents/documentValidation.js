/**
 * Agent 1: Document validation. Load policy from Aurora; validate each document in S3 (exists, size).
 * Persist to agent_executions; update DynamoDB DOCS_TECHNICALLY_VALIDATED.
 */
import { DynamoDBClient, UpdateItemCommand } from '@aws-sdk/client-dynamodb';
import { HeadObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { marshall } from '@aws-sdk/util-dynamodb';
import { loadPolicyByCaseId, loadCaseDocuments } from './policyLoader.js';
import { query } from './db.js';

const dynamo = new DynamoDBClient({});
const s3 = new S3Client({});
const TABLE = process.env.CASE_STATE_TABLE;

export async function handler(event) {
  const detail = event.detail ?? event;
  const caseId = detail.caseId;
  const orgId = detail.orgId;
  if (!caseId) throw new Error('Missing caseId');

  const startedAt = new Date().toISOString();
  const policy = await loadPolicyByCaseId(caseId);
  if (!policy) throw new Error(`Case or policy not found: ${caseId}`);

  const caseDocs = await loadCaseDocuments(caseId);
  const validationResults = [];
  for (const doc of caseDocs) {
    try {
      const head = await s3.send(new HeadObjectCommand({ Bucket: doc.s3_bucket, Key: doc.s3_object_path }));
      validationResults.push({
        documentType: doc.document_type,
        caseDocumentId: doc.case_document_id,
        valid: true,
        size: head.ContentLength,
        contentType: head.ContentType || 'application/octet-stream',
      });
    } catch (err) {
      validationResults.push({
        documentType: doc.document_type,
        caseDocumentId: doc.case_document_id,
        valid: false,
        error: err.message,
      });
      throw new Error(`Document validation failed: ${doc.s3_object_path}`);
    }
  }

  const completedAt = new Date().toISOString();
  const executionId = `ae-docval-${caseId}-${Date.now()}`;
  await query(
    `INSERT INTO agent_executions (agent_execution_id, case_id, agent_name, status, started_at, completed_at, output)
     VALUES ($1, $2, $3, $4, $5::timestamptz, $6::timestamptz, $7::jsonb)`,
    [
      executionId,
      caseId,
      'document_validation',
      'success',
      startedAt,
      completedAt,
      JSON.stringify({ validationResults, documentCount: caseDocs.length }),
    ]
  );

  await dynamo.send(new UpdateItemCommand({
    TableName: TABLE,
    Key: marshall({ case_id: caseId }),
    UpdateExpression: 'SET #status = :status, updated_at = :now',
    ExpressionAttributeNames: { '#status': 'status' },
    ExpressionAttributeValues: marshall({
      ':status': 'DOCS_TECHNICALLY_VALIDATED',
      ':now': completedAt,
    }),
  }));

  return {
    caseId,
    orgId,
    status: 'DOCS_TECHNICALLY_VALIDATED',
    validationResults,
    executedAt: completedAt,
  };
}

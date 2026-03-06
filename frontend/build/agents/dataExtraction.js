/**
 * Agent 2: Data extraction. Load policy and case documents from Aurora; Textract for extraction;
 * persist to extracted_case_data and agent_executions; update DynamoDB DATA_EXTRACTED.
 */
import { DynamoDBClient, UpdateItemCommand } from '@aws-sdk/client-dynamodb';
import { GetObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { TextractClient, AnalyzeDocumentCommand } from '@aws-sdk/client-textract';
import { BedrockRuntimeClient, InvokeModelCommand } from '@aws-sdk/client-bedrock-runtime';
import { marshall } from '@aws-sdk/util-dynamodb';
import { loadPolicyByCaseId, loadCaseDocuments } from './policyLoader.js';
import { query } from './db.js';

const dynamo = new DynamoDBClient({});
const s3 = new S3Client({});
const textract = new TextractClient({});
const bedrock = new BedrockRuntimeClient({});
const TABLE = process.env.CASE_STATE_TABLE;
const MODEL_ID = process.env.BEDROCK_MODEL_ID || 'anthropic.claude-3-sonnet-20240229-v1:0';

export async function handler(event) {
  const detail = event.detail ?? event;
  const caseId = detail.caseId;
  if (!caseId) throw new Error('Missing caseId');

  const startedAt = new Date().toISOString();
  const policy = await loadPolicyByCaseId(caseId);
  if (!policy) throw new Error(`Case or policy not found: ${caseId}`);

  const caseDocs = await loadCaseDocuments(caseId);
  const fieldNames = [...new Set(policy.rules?.map((r) => r.field_name) || [])];
  let combinedText = '';

  for (const doc of caseDocs) {
    const obj = await s3.send(new GetObjectCommand({ Bucket: doc.s3_bucket, Key: doc.s3_object_path }));
    const bytes = await streamToBuffer(obj.Body);
    const textractOut = await textract.send(
      new AnalyzeDocumentCommand({
        Document: { Bytes: bytes },
        FeatureTypes: ['TABLES', 'FORMS'],
      })
    );
    const textBlocks = (textractOut.Blocks || [])
      .filter((b) => b.BlockType === 'LINE' && b.Text)
      .map((b) => b.Text)
      .join(' ');
    combinedText += (combinedText ? ' ' : '') + (textBlocks || '');
  }

  const extracted = [];
  for (const fieldName of fieldNames) {
    const value = await extractFieldWithBedrock(combinedText, fieldName);
    const extId = `ecd-${caseId}-${fieldName}-${Date.now()}`;
    await query(
      `INSERT INTO extracted_case_data (extracted_data_id, case_id, field_name, value, confidence_score, agent_name)
       VALUES ($1, $2, $3, $4::jsonb, $5, $6)`,
      [extId, caseId, fieldName, JSON.stringify(value), 0.85, 'data_extraction']
    );
    extracted.push({ field_name: fieldName, value });
  }

  const completedAt = new Date().toISOString();
  const executionId = `ae-extract-${caseId}-${Date.now()}`;
  await query(
    `INSERT INTO agent_executions (agent_execution_id, case_id, agent_name, status, started_at, completed_at, output, model_version)
     VALUES ($1, $2, $3, $4, $5::timestamptz, $6::timestamptz, $7::jsonb, $8)`,
    [executionId, caseId, 'data_extraction', 'success', startedAt, completedAt, JSON.stringify({ extractedCount: extracted.length }), MODEL_ID]
  );

  await dynamo.send(new UpdateItemCommand({
    TableName: TABLE,
    Key: marshall({ case_id: caseId }),
    UpdateExpression: 'SET #status = :status, updated_at = :now',
    ExpressionAttributeNames: { '#status': 'status' },
    ExpressionAttributeValues: marshall({
      ':status': 'DATA_EXTRACTED',
      ':now': completedAt,
    }),
  }));

  return {
    caseId,
    status: 'DATA_EXTRACTED',
    extractedData: extracted,
    executedAt: completedAt,
    modelVersion: MODEL_ID,
  };
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks);
}

async function extractFieldWithBedrock(text, fieldName) {
  try {
    const payload = {
      anthropic_version: 'bedrock-2023-05-31',
      max_tokens: 256,
      messages: [
        {
          role: 'user',
          content: `From this document text, extract the value for field "${fieldName}". Reply with only the value or "NOT_FOUND".\n\nDocument text:\n${text.slice(0, 8000)}`,
        },
      ],
    };
    const res = await bedrock.send(
      new InvokeModelCommand({
        modelId: MODEL_ID,
        contentType: 'application/json',
        accept: 'application/json',
        body: JSON.stringify(payload),
      })
    );
    const body = JSON.parse(new TextDecoder().decode(res.body));
    const value = body.content?.[0]?.text?.trim() || 'NOT_FOUND';
    return value;
  } catch {
    return 'NOT_FOUND';
  }
}

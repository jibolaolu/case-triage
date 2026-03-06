/**
 * Data Lifecycle Lambda – Automated data deletion after retention period (P0).
 * Triggered by EventBridge schedule (daily).
 * Deletes cases older than retention period (5 years default).
 */
import { getPool } from './db.js';
import { S3Client, DeleteObjectCommand } from '@aws-sdk/client-s3';

const s3 = new S3Client({});
const RETENTION_YEARS = parseInt(process.env.RETENTION_YEARS || '5', 10);
const ENVIRONMENT = process.env.ENVIRONMENT || 'dev';

export async function handler(event) {
  const pool = await getPool();
  const client = await pool.connect();
  try {
    const cutoffDate = new Date();
    cutoffDate.setFullYear(cutoffDate.getFullYear() - RETENTION_YEARS);
    const cutoffISO = cutoffDate.toISOString();

    console.log(JSON.stringify({ message: `Starting data lifecycle cleanup for cases older than ${cutoffISO}`, level: 'INFO' }));

    // Find cases older than retention period
    const oldCases = await client.query(
      `SELECT case_id, organisation_id, case_type_id 
       FROM cases 
       WHERE created_at < $1 
       AND status IN ('APPROVED', 'DECLINED', 'ARCHIVED')
       LIMIT 100`,
      [cutoffISO]
    );

    let deletedCount = 0;
    let errorCount = 0;

    for (const row of oldCases.rows) {
      try {
        await client.query('BEGIN');

        // Delete case documents from S3
        const documents = await client.query(
          'SELECT s3_bucket, s3_object_path FROM case_documents WHERE case_id = $1',
          [row.case_id]
        );

        for (const doc of documents.rows) {
          try {
            await s3.send(new DeleteObjectCommand({
              Bucket: doc.s3_bucket,
              Key: doc.s3_object_path,
            }));
          } catch (err) {
            console.log(JSON.stringify({ message: `Failed to delete S3 object: ${doc.s3_object_path}`, level: 'WARN', error: err.message }));
          }
        }

        // Delete related data
        await client.query('DELETE FROM rule_evaluations WHERE case_id = $1', [row.case_id]);
        await client.query('DELETE FROM extracted_case_data WHERE case_id = $1', [row.case_id]);
        await client.query('DELETE FROM agent_executions WHERE case_id = $1', [row.case_id]);
        await client.query('DELETE FROM case_documents WHERE case_id = $1', [row.case_id]);
        await client.query('DELETE FROM case_decisions WHERE case_id = $1', [row.case_id]);
        await client.query('DELETE FROM audit_logs WHERE entity_type = $1 AND entity_id = $2', ['case', row.case_id]);

        // Soft delete case (or hard delete if policy allows)
        await client.query('DELETE FROM cases WHERE case_id = $1', [row.case_id]);

        await client.query('COMMIT');
        deletedCount++;
        console.log(JSON.stringify({ message: `Deleted case: ${row.case_id}`, level: 'INFO', caseId: row.case_id, organisationId: row.organisation_id }));
      } catch (err) {
        await client.query('ROLLBACK').catch(() => {});
        errorCount++;
        console.log(JSON.stringify({ message: `Failed to delete case: ${row.case_id}`, level: 'ERROR', error: err.message, caseId: row.case_id }));
      }
    }

    console.log(JSON.stringify({
      message: 'Data lifecycle cleanup completed',
      level: 'INFO',
      deletedCount,
      errorCount,
      totalProcessed: oldCases.rows.length,
    }));

    return {
      statusCode: 200,
      body: JSON.stringify({
        deletedCount,
        errorCount,
        totalProcessed: oldCases.rows.length,
        cutoffDate: cutoffISO,
      }),
    };
  } catch (err) {
    console.log(JSON.stringify({ message: 'Data lifecycle cleanup failed', level: 'ERROR', error: err.message, stack: err.stack }));
    throw err;
  } finally {
    client.release();
  }
}

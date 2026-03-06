/**
 * Invoked by SQS when CASE_INTAKE_VALIDATED is delivered to intake-events queue.
 * Starts Step Functions execution with the event body as input.
 */
import { SFNClient, StartExecutionCommand } from '@aws-sdk/client-sfn';

const sfn = new SFNClient({});
const STATE_MACHINE_ARN = process.env.STEP_FUNCTION_ARN;

export async function handler(event) {
  if (!STATE_MACHINE_ARN) throw new Error('STEP_FUNCTION_ARN not set');
  const results = [];
  for (const record of event.Records || []) {
    let body;
    try {
      body = typeof record.body === 'string' ? JSON.parse(record.body) : record.body;
    } catch (e) {
      console.error('Invalid SQS body', e);
      throw e;
    }
    const input = {
      detail: body.detail || body,
      'detail-type': body['detail-type'] || body.detailType,
      source: body.source,
    };
    const out = await sfn.send(new StartExecutionCommand({
      stateMachineArn: STATE_MACHINE_ARN,
      input: JSON.stringify(input),
    }));
    results.push({ executionArn: out.executionArn });
  }
  return results;
}

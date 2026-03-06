/**
 * Structured logging and metrics. No PII. Correlation IDs (requestId, caseId, orgId) in logs.
 */

export function log(level, message, meta = {}) {
  const payload = {
    timestamp: new Date().toISOString(),
    level,
    message,
    ...meta,
  };
  console.log(JSON.stringify(payload));
}

export function metric(namespace, name, value, unit = 'Count', dimensions = {}) {
  const payload = {
    _aws: {
      Timestamp: Date.now(),
      CloudWatchMetrics: [{
        Namespace: namespace,
        Dimensions: [Object.keys(dimensions).map(k => [k])],
        Metrics: [{ Name: name, Unit: unit }],
      }],
    },
    [name]: value,
    ...dimensions,
  };
  console.log(JSON.stringify(payload));
}

export function addRequestContext(logMeta, event) {
  const requestId = event?.requestContext?.requestId ?? event?.requestId;
  const caseId = event?.pathParameters?.caseId ?? event?.caseId ?? event?.detail?.caseId;
  const orgId = event?.requestContext?.authorizer?.claims?.['custom:orgId'] ?? event?.orgId ?? event?.detail?.orgId;
  return { requestId, caseId, orgId, ...logMeta };
}

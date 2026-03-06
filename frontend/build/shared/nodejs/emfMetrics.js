/**
 * Emit CloudWatch EMF metrics (log line JSON). Namespace: FastStart.
 */
const NAMESPACE = 'FastStart';
const ENV = process.env.ENVIRONMENT || 'env';

function emf(metrics, dimensions = {}) {
  const ts = Date.now();
  const unit = (name) => (name === 'DecisionLatency' ? 'Milliseconds' : 'Count');
  const aws = {
    Timestamp: ts,
    CloudWatchMetrics: [{
      Namespace: NAMESPACE,
      Dimensions: [['Environment', ...Object.keys(dimensions)].filter(Boolean)],
      Metrics: Object.keys(metrics).map((Name) => ({ Name, Unit: unit(Name) })),
    }],
  };
  const line = { _aws: aws, Environment: ENV, ...dimensions, ...metrics };
  console.log(JSON.stringify(line));
}

export function putAIAgentFailures(count = 1) {
  emf({ AIAgentFailures: count });
}

export function putDecisionLatency(latencyMs) {
  emf({ DecisionLatency: latencyMs });
}

export function putIntakeFailures(count = 1) {
  emf({ IntakeFailures: count });
}

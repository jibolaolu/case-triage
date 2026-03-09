/**
 * PUT /notifications/{notificationId}/read – mark a notification as read.
 */
export async function handler(event) {
  const notificationId = event.pathParameters?.notificationId;
  if (!notificationId) {
    return {
      statusCode: 400,
      body: JSON.stringify({ error: 'notificationId path parameter required' }),
    };
  }
  // Stub: full impl in Terraform (DynamoDB update). Decode base64 composite key if needed.
  return {
    statusCode: 200,
    body: JSON.stringify({ message: 'Notification marked as read' }),
  };
}

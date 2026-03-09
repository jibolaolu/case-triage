/**
 * GET /admin/users – list all users (e.g. from Cognito User Pool).
 * Spec: returns users with id, name, email, role, status, department, casesAssigned, lastLogin, createdAt.
 */
export async function handler() {
  // Stub: full impl in Terraform list_users (Cognito ListUsers + custom attributes).
  const users = [];
  return {
    statusCode: 200,
    body: JSON.stringify({ users }),
  };
}

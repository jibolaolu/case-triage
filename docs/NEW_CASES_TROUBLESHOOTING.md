# New Cases Not Showing — Checklist and Wiring

If new cases from intake still don’t appear in the portal, use this to verify every link in the chain.

---

## 1. Portal → API URL

The portal must call the **same** API Gateway that exposes **GET /cases** (the one that uses the **list_cases** Lambda and DynamoDB).

| Where | What to check |
|-------|----------------|
| **Amplify** | App env var `NEXT_PUBLIC_API_URL` = API Gateway base URL (e.g. `https://abc123.execute-api.eu-west-2.amazonaws.com/dev`). Set in Terraform via `module.amplify` ← `api_gateway_url = module.api_gateway.base_url`. |
| **Local dev** | `.env.local` or env: `NEXT_PUBLIC_API_URL=https://YOUR_API_ID.execute-api.eu-west-2.amazonaws.com/dev` (same base URL, no `/cases`). |
| **Build** | Amplify build spec writes `NEXT_PUBLIC_API_URL` into `.env.production` so the built app has the correct base URL. |

**Check:** In the browser, open DevTools → Network. Go to Case Management. Find the request to `/cases`. Its full URL should be `https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/cases`. If the host is your Amplify domain or localhost, the app is not using the API Gateway URL (env not set or wrong).

---

## 2. API Gateway → list_cases Lambda

GET /cases must be wired to the **list_cases** Lambda (which reads DynamoDB).

| Where | What to check |
|-------|----------------|
| **Terraform** | `module.api_cases` adds resource `/cases` and method GET → integration to `var.list_cases_invoke_arn` (from `module.lambda`). Same REST API as `module.api_gateway` (same `api_id`). |
| **Stage** | After apply, the stage (e.g. `dev`) must point to a deployment that includes the cases routes. `api_cases` updates the stage to its deployment. |

**Check:** Call the API directly (no browser):

```bash
curl -s -o /dev/null -w "%{http_code}" "https://YOUR_API_ID.execute-api.eu-west-2.amazonaws.com/dev/cases"
```

- **401** = Route exists, Cognito required (expected without a token).
- **404** = Route missing or wrong stage/deployment.
- **500** = Lambda or DynamoDB issue.

---

## 3. list_cases Lambda → DynamoDB table

The Lambda must read from the **case_runtime_state** table (same one intake writes to).

| Where | What to check |
|-------|----------------|
| **Env** | Lambda env `DYNAMODB_TABLE` = table name (e.g. `case-triage-dev-case-runtime-state`). In Terraform: `module.lambda` uses `local.common_env` which includes `DYNAMODB_TABLE = var.dynamodb_table_name` ← `module.dynamodb.table_name`. |
| **Same table as intake** | `application_init` and `application_finalize` use the same `var.dynamodb_table_name` in the Lambda module. So new cases from intake are written to the same table list_cases reads. |

**Check:** In AWS Console → Lambda → list-cases → Configuration → Environment variables. `DYNAMODB_TABLE` should match the DynamoDB table name (e.g. `case-triage-dev-case-runtime-state`). In DynamoDB → Tables, that table should contain items created by intake (caseId, status, etc.).

---

## 4. Auth (why you might see “Could not load cases from server”)

GET /cases is protected by **Cognito**. If the portal uses **demo login** (pick a user, no real Cognito token), the request is sent **without a valid JWT** → API Gateway returns **401** → the portal shows the error banner and an empty list (no mock), so new cases don’t appear.

| Option | Action |
|--------|--------|
| **Use Cognito** | Sign in via Cognito (e.g. Hosted UI or InitiateAuth) so the app has an IdToken. The client sends `Authorization: Bearer <token>` and GET /cases returns DynamoDB data (old + new cases). |
| **Dev bypass** | For local/dev only, you could add a second route GET /cases that doesn’t use the Cognito authorizer (e.g. API key or no auth). Not recommended for production. |

**Check:** In DevTools → Network → request to `.../cases` → Headers. There should be `Authorization: Bearer <long-jwt>`. If there is no Authorization or it’s short/wrong, the app is not using a Cognito token.

---

## 5. Intake → same DynamoDB table

New cases appear only if they’re written to the **same** table list_cases reads.

| Where | What to check |
|-------|----------------|
| **application_init** | Writes to `DYNAMODB_TABLE` (same variable as list_cases). Terraform passes the same `dynamodb_table_name` to all Lambdas that need it. |
| **Pipeline** | Tech validation, data extraction, case_summary etc. update the same DynamoDB item by caseId. So after intake + pipeline, the item has status, applicantName, etc. |

**Check:** After running intake (POST /applications/init then complete), list the table (e.g. AWS Console → DynamoDB → case_runtime_state → Explore items). You should see an item with that caseId. Then GET /cases with a valid Cognito token should return it (and sort newest first).

---

## 6. Summary

| # | Check | If wrong |
|---|--------|----------|
| 1 | Portal uses `NEXT_PUBLIC_API_URL` = API Gateway base URL | Set in Amplify app env and/or .env.local; rebuild/redeploy. |
| 2 | GET /cases exists on that API and stage | Run `terraform apply`; confirm api_cases deployment and stage. |
| 3 | list_cases has DYNAMODB_TABLE = case_runtime_state table | Fix Lambda env in Terraform (same as other Lambdas). |
| 4 | Portal sends Cognito Bearer token for GET /cases | Sign in with Cognito; or add dev bypass. |
| 5 | Intake writes to same DynamoDB table | Same Terraform var; no change needed if 3 is correct. |

After fixing 1–4, new cases from intake should appear in the portal when you open Case Management (and refocus the tab), with newest first and no silent fallback to mock.

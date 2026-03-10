# How to Get New Cases Shown in the Portal

The **caseworker portal** lists cases from **GET /cases**. That endpoint is served by the **list_cases** Lambda, which reads from the **DynamoDB** table `case_runtime_state`. So the portal shows whatever is in that table.

---

## See new cases without deleting old / predefined cases

If you want **new cases to appear in the list alongside existing (predefined) cases** and do **not** want to clear the table:

1. **Use the deployed API for the portal**  
   Set `NEXT_PUBLIC_API_URL` to your Terraform API base URL (e.g. `https://xxx.execute-api.eu-west-2.amazonaws.com/dev`). The list then comes from DynamoDB, which can contain both existing and new cases.

2. **Backend: newest first**  
   The **list_cases** Lambda sorts the list by **updatedAt/createdAt descending**, so the newest cases (including newly created ones from intake) appear at the **top** of the list. No deletion of old data.

3. **Frontend: list refreshes**  
   The portal’s cases list:
   - **Refetches when you focus the tab/window** (`refetchOnWindowFocus`).
   - Treats data as stale after 30 seconds, so reopening the Case Management page or refocusing the window shows new cases without a full page reload.

4. **Where “predefined” cases live**  
   - If they are **in DynamoDB** (e.g. seeded or from earlier intake), they stay there and will appear together with new cases from intake.  
   - If they exist only in the **frontend mock** (`mockCases`), they are shown only when the API fails or returns no cases. To have one single list (old + new) from the API, seed those predefined cases into DynamoDB (e.g. via a one-off script or Terraform null_resource that calls PutItem for each), then the API will return both predefined and new cases.

**Summary:** Point the portal at the deployed API, deploy the updated **list_cases** (sort) and **useCases** (refetch) changes, and create new cases via intake; they will show at the top of the list without deleting any old or predefined cases.

---

- **“Old” cases** = items that were left in DynamoDB from earlier runs (e.g. previous intake/pipeline runs).
- **“New” cases** = items created in the current environment. They are created by the **intake flow** and updated by the **pipeline**.

You do **not** need to persist cases forever. If you **destroy** the stack, DynamoDB is destroyed too, so the next **apply** gives you an empty table and only new cases will appear.

---

## 1. Ensure the Portal Uses the Deployed API

The portal must call your **Terraform-deployed API** (not a local or mock backend):

- **Amplify:** `api_gateway_url` is passed into the Amplify app and set as `NEXT_PUBLIC_API_URL`. So the built app already calls `GET https://<api-id>.execute-api.<region>.amazonaws.com/<stage>/cases`.
- **Local dev:** In `.env.local` (or env) set:
  ```bash
  NEXT_PUBLIC_API_URL=https://YOUR_API_ID.execute-api.eu-west-2.amazonaws.com/dev
  ```
  Use the same base URL as your deployed API (no `/cases` at the end).

If the portal instead used the **Node build API** (Aurora), you would see “old” rows from the database. With the Terraform API, you see DynamoDB.

---

## 2. Get a Fresh List (Only New Cases) — Two Options

### Option A: Destroy and Re-Apply (recommended if you want “no persistence”)

1. **Destroy the stack:**
   ```bash
   cd terraform
   terraform destroy
   ```
   This deletes the DynamoDB table (and the rest of the stack).

2. **Re-apply:**
   ```bash
   terraform apply
   ```
   DynamoDB is recreated **empty**. The portal will show **no cases** until you create new ones.

3. **Create new cases** via the intake flow (see section 3). Those will appear in the portal and will **disappear again** on the next destroy.

### Option B: Clear Only the DynamoDB Table (keep the rest of the stack)

If you don’t want to destroy the whole stack but want to wipe existing cases:

1. **Get the table name** (from Terraform or AWS console):
   - Default pattern: `case-triage-dev-case-runtime-state` (prefix from your `var.project_name` and `var.environment`).

2. **Clear all items** in that table. Easiest: use the provided script (requires `jq` and AWS CLI):
   ```bash
   ./scripts/clear-case-runtime-table.sh case-triage-dev-case-runtime-state eu-west-2
   ```
   Table name is `<project_name>-<environment>-case-runtime-state` (default: `case-triage-dev-case-runtime-state`). Region should match your Terraform `aws_region` (default `eu-west-2`).

After that, the portal will show an empty list until you create new cases. New cases will again disappear if you later run **terraform destroy** (because the table is removed).

---

## 3. Create New Cases So They Show in the Portal

New cases are created by the **application intake** flow and then updated by the pipeline:

1. **POST /applications/init**  
   - Creates a new item in DynamoDB with status `AWAITING_DOCUMENTS`.  
   - This case **will already appear** in the portal list (with minimal fields) if the portal calls GET /cases.

2. **Upload documents** to the presigned S3 URLs returned from init.

3. **POST /applications/complete**  
   - Marks intake complete and triggers the pipeline (tech validation → data extraction → policy evaluation → case summary).  
   - Each step updates the **same** DynamoDB item (status, applicantName, applicationType, priority, aiConfidence, etc.).  
   - The portal’s **GET /cases** reads from that table, so the case will show with updated data as the pipeline runs.

So:

- **To see new cases:** Use the intake app (or API) to call **init** (and optionally **complete**).  
- **To have “new only” and “disappear on destroy”:** Use **Option A** (destroy + apply) when you want a clean slate, or **Option B** (clear table) when you want to keep the stack but reset cases.

---

## 4. Quick Reference

| Goal                         | Action |
|-----------------------------|--------|
| Portal shows only new cases | Clear DynamoDB (Option B) or destroy + apply (Option A). |
| New cases disappear on destroy | Use Terraform for DynamoDB; run `terraform destroy` when you want to wipe everything. |
| Create a new case           | POST /applications/init (then upload docs, then POST /applications/complete). |
| Where the list comes from   | **GET /cases** → list_cases Lambda → DynamoDB table `case_runtime_state`. |

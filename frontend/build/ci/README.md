# FastStart CI/CD (GitLab)

The repository uses **GitLab CI/CD** only. Pipeline definition: **`build/ci/.gitlab-ci.yml`**.

**Important:** In GitLab, set the custom CI config path so pipelines use this file: **Settings → General → CI/CD → General pipelines → CI configuration file** → set to `build/ci/.gitlab-ci.yml`.

## Pipeline stages

| Stage         | Jobs              | When        | Description |
|---------------|-------------------|------------|-------------|
| **validate**  | validate:terraform| Merge requests | Terraform init (no backend) + validate |
| **plan**      | plan:terraform    | Merge requests | Terraform plan, output tfplan |
| **build**     | build:api, build:agents, build:ui | Default branch | Produce api.zip, agents.zip, UI build |
| **deploy-infra** | deploy:infra  | Default branch (manual) | Terraform apply – full infrastructure |
| **deploy-app**   | deploy:lambda  | Default branch (manual) | Update Lambda code from zips |

## Separation: infrastructure vs application

- **Deploy infrastructure** (`deploy:infra`): Runs Terraform init, plan, apply. Creates/updates VPC, Aurora, DynamoDB, S3, Lambda (with placeholder code), API Gateway, Step Functions, EventBridge, etc. Run when IaC or env config changes.
- **Deploy application** (`deploy:lambda`): Uses the built `api.zip` and `agents.zip` to update only Lambda function code via AWS CLI. Run when API or agents code changes, without reapplying Terraform.

## GitLab CI/CD variables

In **Settings → CI/CD → Variables** (masked where possible):

| Variable | Required | Description |
|----------|----------|-------------|
| `AWS_ACCESS_KEY_ID` | Yes (for deploy) | AWS credentials |
| `AWS_SECRET_ACCESS_KEY` | Yes (for deploy) | AWS credentials |
| `AWS_REGION` | No | Override default `us-east-1` |
| `ENVIRONMENT` | No | Override default `dev` |
| `PROJECT_NAME` | No | Override default `FastStart` |

For **plan** on merge requests, Terraform may need backend config. Either configure backend in `build/infrastructure/terraform/environments/dev` or use `terraform init -backend=false` in the validate job only (plan then uses default/empty backend if not configured).

## Usage

1. **Merge requests:** Validate and plan run automatically.
2. **Default branch (e.g. main):** Build runs automatically. In the pipeline, trigger **deploy:infra** (manual) to apply Terraform, then **deploy:lambda** (manual) to update Lambda code when needed.
3. **UI:** Build artifact `build:ui` can be used by Amplify or a separate deploy job (e.g. `aws amplify start-job` for Amplify).

## Optional: AWS CodePipeline

If you later want an AWS-native pipeline (e.g. source from GitLab via CodeStar Connection), see the [Deployment specification](../../specification/DEPLOYMENT.md) for CodeBuild buildspec examples. The same separation (infra deploy vs Lambda code update) can be implemented there.

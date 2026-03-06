"""
Aurora Schema Init Lambda
Runs once after Aurora is provisioned to create all tables.
Invoke manually: aws lambda invoke --function-name case-triage-dev-aurora-schema-init out.json

Tables created (matching HLD v2 Level 9 Data Persistence Layer):
  Case Management:  cases, documents, case_events, decisions, escalations
  Policy Engine:    policies, policy_documents, policy_extraction_fields,
                    policy_rules, policy_fairness_constraints
  AI Agent Outputs: extracted_data, validation_results, eval_outcomes,
                    rule_audit_trail, case_summaries
  Access Control:   organisations, caseworkers, roles, permissions
  Audit:            audit_log
"""

import json
import os
import boto3
import logging

logger = logging.getLogger()
logger.setLevel(logging.INFO)

rds_data = boto3.client("rds-data", region_name=os.environ.get("AWS_REGION", "eu-west-2"))

AURORA_CLUSTER_ARN = os.environ["AURORA_CLUSTER_ARN"]
AURORA_SECRET_ARN  = os.environ["AURORA_SECRET_ARN"]
AURORA_DATABASE    = os.environ["AURORA_DATABASE"]


def _execute(sql: str, description: str = ""):
    """Execute a single DDL statement via RDS Data API."""
    try:
        rds_data.execute_statement(
            resourceArn=AURORA_CLUSTER_ARN,
            secretArn=AURORA_SECRET_ARN,
            database=AURORA_DATABASE,
            sql=sql
        )
        logger.info("✓ %s", description or sql[:80])
    except Exception as e:
        logger.error("✗ %s — %s", description or sql[:80], e)
        raise


# ─── DDL statements in dependency order ──────────────────────────────────────

SCHEMA_DDL = [

    # Extensions
    ("CREATE EXTENSION IF NOT EXISTS pgcrypto",
     "pgcrypto extension (gen_random_uuid)"),

    # ── Access Control ────────────────────────────────────────────────────────

    ("""CREATE TABLE IF NOT EXISTS organisations (
        org_id          VARCHAR(100) PRIMARY KEY,
        org_name        VARCHAR(200) NOT NULL,
        region          VARCHAR(50),
        active          BOOLEAN DEFAULT TRUE,
        created_at      TIMESTAMPTZ DEFAULT NOW()
    )""", "organisations table"),

    ("""CREATE TABLE IF NOT EXISTS roles (
        role_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        role_name       VARCHAR(50) UNIQUE NOT NULL,  -- caseworker, supervisor, admin
        permissions     JSONB DEFAULT '{}'
    )""", "roles table"),

    ("""CREATE TABLE IF NOT EXISTS caseworkers (
        caseworker_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        org_id          VARCHAR(100) REFERENCES organisations(org_id),
        role_id         UUID REFERENCES roles(role_id),
        email           VARCHAR(200) UNIQUE NOT NULL,
        full_name       VARCHAR(200),
        active          BOOLEAN DEFAULT TRUE,
        created_at      TIMESTAMPTZ DEFAULT NOW()
    )""", "caseworkers table"),

    # ── Policy Engine ─────────────────────────────────────────────────────────

    ("""CREATE TABLE IF NOT EXISTS policies (
        policy_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        version         INTEGER NOT NULL,
        org_id          VARCHAR(100) REFERENCES organisations(org_id),
        case_type       VARCHAR(50) NOT NULL,
        sub_type        VARCHAR(50),
        status          VARCHAR(20) DEFAULT 'draft',  -- draft / active / retired
        effective_date  TIMESTAMPTZ,
        retired_date    TIMESTAMPTZ,
        created_by      VARCHAR(200),
        created_at      TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE (org_id, case_type, version)
    )""", "policies table"),

    ("""CREATE TABLE IF NOT EXISTS policy_documents (
        doc_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        policy_id       UUID REFERENCES policies(policy_id),
        document_type   VARCHAR(100) NOT NULL,   -- bank_statement, id_proof, etc.
        mandatory       BOOLEAN DEFAULT TRUE,
        accepted_formats JSONB DEFAULT '["pdf"]'
    )""", "policy_documents table"),

    ("""CREATE TABLE IF NOT EXISTS policy_extraction_fields (
        field_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        policy_id       UUID REFERENCES policies(policy_id),
        field_name      VARCHAR(100) NOT NULL,   -- drives Agent 2 extraction
        data_type       VARCHAR(50) NOT NULL,    -- string / number / date / boolean
        required        BOOLEAN DEFAULT TRUE,
        validation_regex VARCHAR(500)
    )""", "policy_extraction_fields table"),

    ("""CREATE TABLE IF NOT EXISTS policy_rules (
        rule_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        policy_id       UUID REFERENCES policies(policy_id),
        rule_name       VARCHAR(200) NOT NULL,
        field_name      VARCHAR(100) NOT NULL,   -- extracted field to evaluate
        operator        VARCHAR(30) NOT NULL,    -- lt, gt, eq, lte, gte, in_range, not_null
        comparison_value JSONB NOT NULL,         -- threshold value(s)
        is_blocking     BOOLEAN DEFAULT TRUE,    -- false = warning only
        description     TEXT,
        sort_order      INTEGER DEFAULT 0
    )""", "policy_rules table"),

    ("""CREATE TABLE IF NOT EXISTS policy_fairness_constraints (
        constraint_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        policy_id            UUID REFERENCES policies(policy_id),
        prohibited_attribute VARCHAR(100) NOT NULL,
        enforcement_level    VARCHAR(20) DEFAULT 'hard'  -- hard / advisory
    )""", "policy_fairness_constraints table"),

    # ── Case Management ───────────────────────────────────────────────────────

    ("""CREATE TABLE IF NOT EXISTS cases (
        case_id             VARCHAR(100) PRIMARY KEY,
        organisation_id     VARCHAR(100) REFERENCES organisations(org_id),
        policy_id           UUID REFERENCES policies(policy_id) DEFAULT NULL,
        policy_version      INTEGER NOT NULL,
        case_type           VARCHAR(50) NOT NULL,
        sub_type            VARCHAR(50),
        submission_type     VARCHAR(20) DEFAULT 'NEW',  -- NEW / RESUBMISSION / APPEAL
        applicant_reference VARCHAR(200),               -- FK to applicant (future)
        assigned_caseworker UUID REFERENCES caseworkers(caseworker_id),
        created_at          TIMESTAMPTZ DEFAULT NOW(),
        updated_at          TIMESTAMPTZ DEFAULT NOW()
    )""", "cases table"),

    ("""CREATE TABLE IF NOT EXISTS documents (
        document_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id         VARCHAR(100) REFERENCES cases(case_id),
        document_type   VARCHAR(100) NOT NULL,
        s3_key          TEXT NOT NULL,
        s3_bucket       VARCHAR(200),
        version         INTEGER DEFAULT 1,
        file_size_bytes INTEGER,
        mime_type       VARCHAR(100),
        uploaded_at     TIMESTAMPTZ DEFAULT NOW()
    )""", "documents table"),

    ("""CREATE TABLE IF NOT EXISTS case_events (
        event_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id         VARCHAR(100) REFERENCES cases(case_id),
        event_type      VARCHAR(100) NOT NULL,   -- STATUS_CHANGE, AGENT_COMPLETE, etc.
        from_status     VARCHAR(100),
        to_status       VARCHAR(100),
        agent           VARCHAR(100),            -- TechValidation, DataExtraction, etc.
        details         JSONB DEFAULT '{}',
        created_at      TIMESTAMPTZ DEFAULT NOW()
    )""", "case_events table"),

    ("""CREATE TABLE IF NOT EXISTS decisions (
        decision_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id         VARCHAR(100) REFERENCES cases(case_id),
        caseworker_id   UUID REFERENCES caseworkers(caseworker_id),
        outcome         VARCHAR(30) NOT NULL,    -- APPROVED / DECLINED / PENDING / ESCALATED
        notes           TEXT,
        is_mandatory    BOOLEAN DEFAULT FALSE,   -- DECLINED requires mandatory notes
        decided_at      TIMESTAMPTZ DEFAULT NOW()
    )""", "decisions table"),

    ("""CREATE TABLE IF NOT EXISTS escalations (
        escalation_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id         VARCHAR(100) REFERENCES cases(case_id),
        raised_by       UUID REFERENCES caseworkers(caseworker_id),
        reason          TEXT NOT NULL,
        resolved        BOOLEAN DEFAULT FALSE,
        resolved_at     TIMESTAMPTZ,
        created_at      TIMESTAMPTZ DEFAULT NOW()
    )""", "escalations table"),

    # ── AI Agent Outputs (immutable once written) ─────────────────────────────

    ("""CREATE TABLE IF NOT EXISTS validation_results (
        case_id         VARCHAR(100) REFERENCES cases(case_id),
        document_type   VARCHAR(100) NOT NULL,
        is_valid        BOOLEAN,
        file_size_bytes INTEGER,
        mime_type       VARCHAR(100),
        failure_reason  TEXT,
        validated_at    TIMESTAMPTZ DEFAULT NOW(),
        PRIMARY KEY (case_id, document_type)
    )""", "validation_results table"),

    ("""CREATE TABLE IF NOT EXISTS extracted_data (
        case_id         VARCHAR(100) REFERENCES cases(case_id),
        field_name      VARCHAR(100) NOT NULL,
        field_value     TEXT,
        confidence      DECIMAL(5,4),            -- 0.0000 to 1.0000
        source_document VARCHAR(100),            -- which doc the field came from
        extracted_at    TIMESTAMPTZ DEFAULT NOW(),
        PRIMARY KEY (case_id, field_name)
    )""", "extracted_data table"),

    ("""CREATE TABLE IF NOT EXISTS eval_outcomes (
        outcome_id      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id         VARCHAR(100) REFERENCES cases(case_id),
        rule_id         UUID REFERENCES policy_rules(rule_id),
        result          VARCHAR(20) NOT NULL,    -- PASS / FAIL / INCONCLUSIVE
        explanation     TEXT,
        is_blocking     BOOLEAN DEFAULT TRUE,
        evaluated_at    TIMESTAMPTZ DEFAULT NOW(),
        UNIQUE (case_id, rule_id)
    )""", "eval_outcomes table"),

    ("""CREATE TABLE IF NOT EXISTS rule_audit_trail (
        audit_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id         VARCHAR(100) REFERENCES cases(case_id),
        rule_id         UUID REFERENCES policy_rules(rule_id),
        rule_name       VARCHAR(200),
        field_evaluated VARCHAR(100),
        value_found     TEXT,
        threshold_used  JSONB,
        result          VARCHAR(20),
        agent_version   VARCHAR(50),             -- Lambda version at time of evaluation
        created_at      TIMESTAMPTZ DEFAULT NOW()
    )""", "rule_audit_trail table"),

    ("""CREATE TABLE IF NOT EXISTS case_summaries (
        case_id             VARCHAR(100) PRIMARY KEY REFERENCES cases(case_id),
        priority            VARCHAR(20),         -- HIGH / MEDIUM / LOW
        complexity          VARCHAR(20),         -- HIGH / MEDIUM / LOW
        recommendation      TEXT,
        supervisor_review   BOOLEAN DEFAULT FALSE,
        risk_flags          JSONB DEFAULT '[]',
        strengths           JSONB DEFAULT '[]',
        concerns            JSONB DEFAULT '[]',
        model_used          VARCHAR(100),
        summary_json        JSONB,               -- full structured case pack
        created_at          TIMESTAMPTZ DEFAULT NOW()
    )""", "case_summaries table"),

    # ── Audit Log (immutable — append-only) ───────────────────────────────────

    ("""CREATE TABLE IF NOT EXISTS user_preferences (
        user_id         VARCHAR(200) PRIMARY KEY,
        preferences     JSONB DEFAULT '{}',
        updated_at      TIMESTAMPTZ DEFAULT NOW()
    )""", "user_preferences table"),

    ("""CREATE TABLE IF NOT EXISTS audit_log (
        log_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
        case_id         VARCHAR(100),
        actor_type      VARCHAR(50),             -- lambda / caseworker / system
        actor_id        VARCHAR(200),
        action          VARCHAR(100) NOT NULL,
        resource_type   VARCHAR(100),
        resource_id     VARCHAR(200),
        old_value       JSONB,
        new_value       JSONB,
        ip_address      INET,
        created_at      TIMESTAMPTZ DEFAULT NOW()
    )""", "audit_log table"),

    # ── Indexes ───────────────────────────────────────────────────────────────

    ("CREATE INDEX IF NOT EXISTS idx_cases_org        ON cases(organisation_id)",
     "index cases.organisation_id"),
    ("CREATE INDEX IF NOT EXISTS idx_cases_type       ON cases(case_type)",
     "index cases.case_type"),
    ("CREATE INDEX IF NOT EXISTS idx_documents_case   ON documents(case_id)",
     "index documents.case_id"),
    ("CREATE INDEX IF NOT EXISTS idx_events_case      ON case_events(case_id)",
     "index case_events.case_id"),
    ("CREATE INDEX IF NOT EXISTS idx_events_type      ON case_events(event_type)",
     "index case_events.event_type"),
    ("CREATE INDEX IF NOT EXISTS idx_extracted_case   ON extracted_data(case_id)",
     "index extracted_data.case_id"),
    ("CREATE INDEX IF NOT EXISTS idx_eval_case        ON eval_outcomes(case_id)",
     "index eval_outcomes.case_id"),
    ("CREATE INDEX IF NOT EXISTS idx_audit_case       ON audit_log(case_id)",
     "index audit_log.case_id"),
    ("CREATE INDEX IF NOT EXISTS idx_audit_created    ON audit_log(created_at DESC)",
     "index audit_log.created_at"),
    ("CREATE INDEX IF NOT EXISTS idx_policies_active  ON policies(org_id, case_type) WHERE status = 'active'",
     "partial index policies where active"),
    ("CREATE INDEX IF NOT EXISTS idx_rules_policy     ON policy_rules(policy_id)",
     "index policy_rules.policy_id"),

    # ── Seed data — default roles ─────────────────────────────────────────────

    ("""INSERT INTO roles (role_name, permissions)
        VALUES
          ('caseworker', '{"can_view": true, "can_decide": true, "can_escalate": true}'),
          ('supervisor', '{"can_view": true, "can_decide": true, "can_escalate": true, "can_override": true}'),
          ('admin',      '{"can_view": true, "can_decide": true, "can_escalate": true, "can_override": true, "can_manage_policy": true}')
        ON CONFLICT (role_name) DO NOTHING""",
     "seed default roles"),

    # ── Seed data — default organisation ─────────────────────────────────────

    ("""INSERT INTO organisations (org_id, org_name, region)
        VALUES
          ('councilB', 'Council B Housing Department', 'eu-west-2'),
          ('councilA', 'Council A Hardship Fund', 'eu-west-2')
        ON CONFLICT (org_id) DO NOTHING""",
     "seed councilA + councilB organisations"),

    # Seed active policies so policy_id FK can be back-filled later
    # status='active' means the policy rules loader will find them
    ("""INSERT INTO policies (org_id, case_type, version, status, effective_date)
        VALUES
          ('councilB', 'housing-support',  1, 'active', NOW()),
          ('councilA', 'hardship-fund',    1, 'active', NOW()),
          ('councilA', 'emergency-grant',  1, 'active', NOW())
        ON CONFLICT (org_id, case_type, version) DO NOTHING""",
     "seed active policies for all orgs/case-types"),

]


def lambda_handler(event, context):
    """
    Run all DDL statements in order.
    Idempotent — IF NOT EXISTS on all CREATE statements.
    """
    logger.info("Aurora schema initialisation starting")

    results = {"created": [], "failed": [], "total": len(SCHEMA_DDL)}

    for sql, description in SCHEMA_DDL:
        try:
            _execute(sql, description)
            results["created"].append(description)
        except Exception as e:
            results["failed"].append({"description": description, "error": str(e)})

    if results["failed"]:
        logger.error("Schema init completed with %d failures", len(results["failed"]))
        return {"statusCode": 500, "body": json.dumps(results)}

    logger.info("Schema init completed — %d statements executed", len(results["created"]))
    return {"statusCode": 200, "body": json.dumps(results)}

-- FastStart Aurora PostgreSQL – initial schema (specification-aligned)
-- Run after Aurora and RDS Proxy are created. Replace placeholders if needed.

-- Organisations & case setup
CREATE TABLE IF NOT EXISTS organisations (
    organisation_id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'suspended', 'deleted')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS case_types (
    case_type_id VARCHAR(50) PRIMARY KEY,
    organisation_id VARCHAR(50) NOT NULL REFERENCES organisations(organisation_id),
    name VARCHAR(255) NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('active', 'inactive')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Policies (versioned)
CREATE TABLE IF NOT EXISTS policies (
    policy_id VARCHAR(50) PRIMARY KEY,
    organisation_id VARCHAR(50) NOT NULL REFERENCES organisations(organisation_id),
    case_type_id VARCHAR(50) NOT NULL REFERENCES case_types(case_type_id),
    version INTEGER NOT NULL,
    status VARCHAR(20) NOT NULL CHECK (status IN ('draft', 'active', 'retired')),
    effective_from TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_by VARCHAR(100),
    policy_definition JSONB NOT NULL
);

CREATE TABLE IF NOT EXISTS policy_documents (
    policy_document_id VARCHAR(50) PRIMARY KEY,
    policy_id VARCHAR(50) NOT NULL REFERENCES policies(policy_id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL,
    mandatory BOOLEAN NOT NULL DEFAULT false,
    accepted_formats TEXT[] NOT NULL,
    max_versions INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS policy_rules (
    rule_id VARCHAR(50) PRIMARY KEY,
    policy_id VARCHAR(50) NOT NULL REFERENCES policies(policy_id) ON DELETE CASCADE,
    field_name VARCHAR(100) NOT NULL,
    operator VARCHAR(10) NOT NULL,
    comparison_value JSONB NOT NULL,
    description TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Cases & application
CREATE TABLE IF NOT EXISTS cases (
    case_id VARCHAR(100) PRIMARY KEY,
    organisation_id VARCHAR(50) NOT NULL REFERENCES organisations(organisation_id),
    case_type_id VARCHAR(50) NOT NULL REFERENCES case_types(case_type_id),
    policy_id VARCHAR(50) NOT NULL REFERENCES policies(policy_id),
    policy_version INTEGER NOT NULL,
    submission_type VARCHAR(20) NOT NULL,
    applicant_reference VARCHAR(255),
    status VARCHAR(50) NOT NULL,
    assigned_to VARCHAR(100),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    intake_completed_at TIMESTAMPTZ,
    ai_completed_at TIMESTAMPTZ,
    decided_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    archived_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_cases_org ON cases(organisation_id);
CREATE INDEX IF NOT EXISTS idx_cases_status ON cases(organisation_id, status);

CREATE TABLE IF NOT EXISTS case_documents (
    case_document_id VARCHAR(50) PRIMARY KEY,
    case_id VARCHAR(100) NOT NULL REFERENCES cases(case_id) ON DELETE CASCADE,
    document_type VARCHAR(50) NOT NULL,
    s3_object_path VARCHAR(500) NOT NULL,
    s3_bucket VARCHAR(255) NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    upload_timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS extracted_case_data (
    extracted_data_id VARCHAR(50) PRIMARY KEY,
    case_id VARCHAR(100) NOT NULL REFERENCES cases(case_id) ON DELETE CASCADE,
    field_name VARCHAR(100) NOT NULL,
    value JSONB NOT NULL,
    confidence_score DECIMAL(5,4),
    extracted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    agent_name VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS agent_executions (
    agent_execution_id VARCHAR(50) PRIMARY KEY,
    case_id VARCHAR(100) NOT NULL REFERENCES cases(case_id) ON DELETE CASCADE,
    agent_name VARCHAR(100) NOT NULL,
    status VARCHAR(20) NOT NULL,
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    output JSONB,
    model_version VARCHAR(100)
);

CREATE TABLE IF NOT EXISTS rule_evaluations (
    evaluation_id VARCHAR(50) PRIMARY KEY,
    case_id VARCHAR(100) NOT NULL REFERENCES cases(case_id) ON DELETE CASCADE,
    rule_id VARCHAR(50) NOT NULL REFERENCES policy_rules(rule_id),
    result VARCHAR(20) NOT NULL,
    explanation TEXT,
    evaluated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS case_decisions (
    decision_id VARCHAR(50) PRIMARY KEY,
    case_id VARCHAR(100) NOT NULL UNIQUE REFERENCES cases(case_id) ON DELETE CASCADE,
    decision VARCHAR(20) NOT NULL,
    decided_by VARCHAR(100) NOT NULL,
    justification TEXT NOT NULL,
    decided_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
    audit_id VARCHAR(50) PRIMARY KEY,
    entity_type VARCHAR(50) NOT NULL,
    entity_id VARCHAR(100) NOT NULL,
    action VARCHAR(50) NOT NULL,
    performed_by VARCHAR(100) NOT NULL,
    performed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    new_values JSONB
);

CREATE TABLE IF NOT EXISTS users (
    user_id VARCHAR(100) PRIMARY KEY,
    organisation_id VARCHAR(50) NOT NULL REFERENCES organisations(organisation_id),
    email VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL,
    status VARCHAR(20) NOT NULL,
    mfa_enabled BOOLEAN NOT NULL DEFAULT false,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS user_invitations (
    invitation_id VARCHAR(50) PRIMARY KEY,
    user_id VARCHAR(100),
    email VARCHAR(255) NOT NULL,
    organisation_id VARCHAR(50) NOT NULL REFERENCES organisations(organisation_id),
    role VARCHAR(50) NOT NULL,
    invited_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    expires_at TIMESTAMPTZ NOT NULL,
    status VARCHAR(20) NOT NULL
);

/**
 * Core domain types aligned with specification and API contracts.
 */

export type CaseStatus = 'PENDING' | 'IN_PROGRESS' | 'APPROVED' | 'DECLINED' | 'ESCALATED';
export type Priority = 'URGENT' | 'HIGH' | 'STANDARD' | 'LOW';
export type UserRole = 'ADMIN' | 'CASEWORKER' | 'MANAGER';
export type Decision = 'approve' | 'decline' | 'escalate';

export type CaseDocument = {
  id: string;
  name: string;
  type: string;
  uploadedAt: string;
  viewUrl?: string;
  downloadUrl?: string;
};

export type MockCase = {
  id: string;
  applicantName: string;
  applicantEmail: string;
  applicationType: string;
  status: CaseStatus;
  priority: Priority;
  assignedTo: string;       // user id
  assignedToName: string;
  createdAt: string;
  updatedAt: string;
  escalationReason?: string;
  aiConfidence?: number;
  aiRecommendation?: 'APPROVE' | 'DECLINE';
  notes?: string;
  niNumber?: string;
  dob?: string;
  phone?: string;
  documents?: CaseDocument[];
};

export type MockUser = {
  id: string;
  name: string;
  email: string;
  role: UserRole;
  status: 'ACTIVE' | 'INACTIVE';
  department: string;
  casesAssigned: number;
  lastLogin: string;
  createdAt: string;
};

export type NotificationType =
  | 'USER_CREATED'
  | 'ROLE_UPDATED'
  | 'SYSTEM_ALERT'
  | 'ESCALATION_ASSIGNED'
  | 'CASE_APPROVED'
  | 'CASE_DECLINED'
  | 'CASE_ASSIGNED'
  | 'DEADLINE_APPROACHING';

export type MockNotification = {
  id: string;
  type: NotificationType;
  title: string;
  message: string;
  read: boolean;
  createdAt: string;
  caseId?: string;
  visibleTo: UserRole[];
};

export type EmailDraft = {
  caseId: string;
  decision: 'APPROVED' | 'DECLINED' | 'ESCALATED';
  subject: string;
  body: string;
  toAddress: string;
  toName: string;
  justification: string;
};

export type AuthUser = {
  id: string;
  email: string;
  name: string;
  role: UserRole;
};

export type CaseSummary = {
  caseId: string;
  applicantName: string;
  applicationType: string;
  status: CaseStatus;
  priority: Priority;
  assignedTo: string;
  assignedToName: string;
  createdAt: string;
  updatedAt: string;
  aiConfidence?: number;
};

export type CaseDetail = {
  caseId: string;
  status: CaseStatus;
  priority: Priority;
  applicantName: string;
  applicantEmail: string;
  applicationType: string;
  assignedTo: string;
  assignedToName: string;
  createdAt: string;
  updatedAt: string;
  submittedAt: string;
  escalationReason?: string;
  aiConfidence?: number;
  aiRecommendation?: 'APPROVE' | 'DECLINE';
  notes?: string;
  niNumber?: string;
  dob?: string;
  phone?: string;
  documents?: CaseDocument[];
  auditTrail?: AuditEvent[];
  aiSummary?: string;
  validationResults?: Array<{ rule: string; passed: boolean; detail?: string }>;
  extractedData?: Record<string, unknown>;
};

export type AuditEvent = {
  caseId: string;
  eventAt: string;
  agent: string;
  action: string;
  detail?: Record<string, unknown>;
};

export type Notification = {
  id: string;
  type: string;
  title: string;
  message: string;
  read: boolean;
  createdAt: string;
  caseId?: string;
};

export type Policy = {
  id: string;
  name: string;
  category: string;
  version: string;
  status: string;
  content?: string;
  createdAt: string;
  updatedAt: string;
};

export type UserProfile = {
  id: string;
  name: string;
  email: string;
  role: UserRole;
  department?: string;
  phone?: string;
  preferences?: {
    notifications?: Record<string, boolean>;
    theme?: string;
  };
};

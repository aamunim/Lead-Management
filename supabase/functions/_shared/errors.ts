// Error contract (0A.06-T5, principle 10): every RPC / Edge Function error has a stable code and a user-safe
// message key (translated in the app). The UI shows an error state with Retry — never an empty list.
// Codes raised by the database (docs/dev/TENANCY.md) are mapped here so the app reacts the same way everywhere.

export type ErrorAction = 'sign_in' | 'choose_institution' | 'refresh_session' | 'upgrade_app' | 'fix_input' | 'retry' | 'none';

export type ErrorInfo = { code: string; messageKey: string; httpStatus: number; action: ErrorAction };

export const ERRORS: Record<string, ErrorInfo> = {
  not_signed_in: { code: 'not_signed_in', messageKey: 'errors.not_signed_in', httpStatus: 401, action: 'sign_in' },
  no_active_institution: {
    code: 'no_active_institution', messageKey: 'errors.no_active_institution', httpStatus: 409, action: 'choose_institution',
  },
  membership_not_active: {
    code: 'membership_not_active', messageKey: 'errors.membership_not_active', httpStatus: 403, action: 'choose_institution',
  },
  session_refresh_required: {
    code: 'session_refresh_required', messageKey: 'errors.session_refresh_required', httpStatus: 409, action: 'refresh_session',
  },
  upgrade_required: { code: 'upgrade_required', messageKey: 'errors.upgrade_required', httpStatus: 426, action: 'upgrade_app' },
  setting_invalid: { code: 'setting_invalid', messageKey: 'errors.setting_invalid', httpStatus: 422, action: 'fix_input' },
  setting_unknown: { code: 'setting_unknown', messageKey: 'errors.unknown', httpStatus: 404, action: 'none' },
  not_a_member: { code: 'not_a_member', messageKey: 'errors.not_a_member', httpStatus: 403, action: 'none' },
  institution_mismatch: { code: 'institution_mismatch', messageKey: 'errors.forbidden', httpStatus: 403, action: 'none' },
  protected_column: { code: 'protected_column', messageKey: 'errors.forbidden', httpStatus: 403, action: 'none' },
  permission_denied: { code: 'permission_denied', messageKey: 'errors.forbidden', httpStatus: 403, action: 'none' },
  language_unsupported: { code: 'language_unsupported', messageKey: 'errors.language_unsupported', httpStatus: 422, action: 'fix_input' },
  extension_disabled: { code: 'extension_disabled', messageKey: 'errors.extension_disabled', httpStatus: 403, action: 'none' },
  phone_invalid: { code: 'phone_invalid', messageKey: 'errors.phone_invalid', httpStatus: 422, action: 'fix_input' },
  number_invalid: { code: 'number_invalid', messageKey: 'errors.number_invalid', httpStatus: 422, action: 'fix_input' },
  label_unknown: { code: 'label_unknown', messageKey: 'errors.unknown', httpStatus: 404, action: 'none' },
  label_invalid: { code: 'label_invalid', messageKey: 'errors.label_invalid', httpStatus: 422, action: 'fix_input' },
  label_too_long: { code: 'label_too_long', messageKey: 'errors.label_too_long', httpStatus: 422, action: 'fix_input' },
  label_locked: { code: 'label_locked', messageKey: 'errors.label_locked', httpStatus: 423, action: 'none' },
  label_not_lockable: { code: 'label_not_lockable', messageKey: 'errors.unknown', httpStatus: 422, action: 'none' },
  org_unit_unknown: { code: 'org_unit_unknown', messageKey: 'errors.org_unit_unknown', httpStatus: 404, action: 'retry' },
  org_unit_invalid: { code: 'org_unit_invalid', messageKey: 'errors.org_unit_invalid', httpStatus: 422, action: 'fix_input' },
  org_unit_cycle: { code: 'org_unit_cycle', messageKey: 'errors.org_unit_cycle', httpStatus: 422, action: 'fix_input' },
  org_unit_archived: { code: 'org_unit_archived', messageKey: 'errors.org_unit_archived', httpStatus: 422, action: 'fix_input' },
  org_unit_not_empty: { code: 'org_unit_not_empty', messageKey: 'errors.org_unit_not_empty', httpStatus: 409, action: 'none' },
  branches_disabled: { code: 'branches_disabled', messageKey: 'errors.branches_disabled', httpStatus: 403, action: 'none' },
  role_unknown: { code: 'role_unknown', messageKey: 'errors.unknown', httpStatus: 404, action: 'retry' },
  role_invalid: { code: 'role_invalid', messageKey: 'errors.role_invalid', httpStatus: 422, action: 'fix_input' },
  mfa_required: { code: 'mfa_required', messageKey: 'errors.mfa_required', httpStatus: 401, action: 'sign_in' },
  who_invalid: { code: 'who_invalid', messageKey: 'errors.setting_invalid', httpStatus: 422, action: 'fix_input' },
  permission_escalation: { code: 'permission_escalation', messageKey: 'errors.permission_escalation', httpStatus: 403, action: 'none' },
  last_super_admin: { code: 'last_super_admin', messageKey: 'errors.last_super_admin', httpStatus: 409, action: 'none' },
  self_lockout: { code: 'self_lockout', messageKey: 'errors.self_lockout', httpStatus: 409, action: 'none' },
  role_has_members: { code: 'role_has_members', messageKey: 'errors.role_has_members', httpStatus: 409, action: 'fix_input' },
  user_unknown: { code: 'user_unknown', messageKey: 'errors.user_unknown', httpStatus: 404, action: 'retry' },
  user_state_invalid: { code: 'user_state_invalid', messageKey: 'errors.user_state_invalid', httpStatus: 409, action: 'retry' },
  user_contact_invalid: { code: 'user_contact_invalid', messageKey: 'errors.user_contact_invalid', httpStatus: 422, action: 'fix_input' },
  profile_invalid: { code: 'profile_invalid', messageKey: 'errors.profile_invalid', httpStatus: 422, action: 'fix_input' },
  version_published: { code: 'version_published', messageKey: 'errors.version_published', httpStatus: 409, action: 'none' },
  version_unknown: { code: 'version_unknown', messageKey: 'errors.version_unknown', httpStatus: 404, action: 'retry' },
  industry_not_ready: { code: 'industry_not_ready', messageKey: 'errors.industry_not_ready', httpStatus: 409, action: 'none' },
  kind_invalid: { code: 'kind_invalid', messageKey: 'errors.unknown', httpStatus: 422, action: 'none' },
  profile_choice_invalid: { code: 'profile_choice_invalid', messageKey: 'errors.profile_choice_invalid', httpStatus: 422, action: 'fix_input' },
  limit_reached: { code: 'limit_reached', messageKey: 'errors.limit_reached', httpStatus: 429, action: 'none' },
  module_not_in_plan: { code: 'module_not_in_plan', messageKey: 'errors.module_not_in_plan', httpStatus: 403, action: 'none' },
  module_always_on: { code: 'module_always_on', messageKey: 'errors.module_always_on', httpStatus: 409, action: 'none' },
  module_needs_other: { code: 'module_needs_other', messageKey: 'errors.module_needs_other', httpStatus: 409, action: 'none' },
  module_unknown: { code: 'module_unknown', messageKey: 'errors.unknown', httpStatus: 404, action: 'none' },
  plan_invalid: { code: 'plan_invalid', messageKey: 'errors.plan_invalid', httpStatus: 422, action: 'fix_input' },
  custom_field_invalid: { code: 'custom_field_invalid', messageKey: 'errors.custom_field_invalid', httpStatus: 422, action: 'fix_input' },
  institution_read_only: { code: 'institution_read_only', messageKey: 'errors.institution_read_only', httpStatus: 423, action: 'none' },
  institution_suspended: { code: 'institution_suspended', messageKey: 'errors.institution_suspended', httpStatus: 403, action: 'choose_institution' },
  institution_closed: { code: 'institution_closed', messageKey: 'errors.institution_closed', httpStatus: 403, action: 'choose_institution' },
  status_transition_invalid: { code: 'status_transition_invalid', messageKey: 'errors.status_transition_invalid', httpStatus: 409, action: 'none' },
  reason_required: { code: 'reason_required', messageKey: 'errors.reason_required', httpStatus: 422, action: 'fix_input' },
  export_required: { code: 'export_required', messageKey: 'errors.export_required', httpStatus: 409, action: 'none' },
  support_read_only: { code: 'support_read_only', messageKey: 'errors.support_read_only', httpStatus: 423, action: 'none' },
  support_session_ended: { code: 'support_session_ended', messageKey: 'errors.support_session_ended', httpStatus: 401, action: 'refresh_session' },
  support_minutes_invalid: { code: 'support_minutes_invalid', messageKey: 'errors.support_minutes_invalid', httpStatus: 422, action: 'fix_input' },
  signup_invalid: { code: 'signup_invalid', messageKey: 'errors.signup_invalid', httpStatus: 422, action: 'fix_input' },
  signup_rate_limited: { code: 'signup_rate_limited', messageKey: 'errors.signup_rate_limited', httpStatus: 429, action: 'none' },
  signup_closed: { code: 'signup_closed', messageKey: 'errors.signup_closed', httpStatus: 403, action: 'none' },
  request_key_required: { code: 'request_key_required', messageKey: 'errors.unknown', httpStatus: 422, action: 'none' },
  super_admin_role_missing: { code: 'super_admin_role_missing', messageKey: 'errors.unknown', httpStatus: 500, action: 'none' },
  checklist_item_locked: { code: 'checklist_item_locked', messageKey: 'errors.checklist_item_locked', httpStatus: 409, action: 'none' },
  branding_invalid: { code: 'branding_invalid', messageKey: 'errors.branding_invalid', httpStatus: 422, action: 'fix_input' },
  copy_source_invalid: { code: 'copy_source_invalid', messageKey: 'errors.copy_source_invalid', httpStatus: 422, action: 'fix_input' },
  connection_invalid: { code: 'connection_invalid', messageKey: 'errors.connection_invalid', httpStatus: 422, action: 'fix_input' },
  secret_value_invalid: { code: 'secret_value_invalid', messageKey: 'errors.secret_value_invalid', httpStatus: 422, action: 'fix_input' },
  secret_valid_from_in_past: { code: 'secret_valid_from_in_past', messageKey: 'errors.secret_valid_from_in_past', httpStatus: 422, action: 'fix_input' },
  outbox_invalid: { code: 'outbox_invalid', messageKey: 'errors.outbox_invalid', httpStatus: 422, action: 'fix_input' },
  not_approved: { code: 'not_approved', messageKey: 'errors.not_approved', httpStatus: 403, action: 'none' },
  domain_taken: { code: 'domain_taken', messageKey: 'errors.domain_taken', httpStatus: 409, action: 'fix_input' },
  sender_paused: { code: 'sender_paused', messageKey: 'errors.sender_paused', httpStatus: 423, action: 'none' },
  domain_not_verified: { code: 'domain_not_verified', messageKey: 'errors.domain_not_verified', httpStatus: 409, action: 'none' },
  template_unknown: { code: 'template_unknown', messageKey: 'errors.template_unknown', httpStatus: 404, action: 'none' },
  self_approval: { code: 'self_approval', messageKey: 'errors.self_approval', httpStatus: 409, action: 'none' },
  profile_shared: { code: 'profile_shared', messageKey: 'errors.profile_shared', httpStatus: 409, action: 'none' },
  email_invalid: { code: 'email_invalid', messageKey: 'errors.email_invalid', httpStatus: 422, action: 'fix_input' },
  email_taken: { code: 'email_taken', messageKey: 'errors.email_taken', httpStatus: 409, action: 'fix_input' },
  record_unknown: { code: 'record_unknown', messageKey: 'errors.record_unknown', httpStatus: 404, action: 'fix_input' },
  permission_unknown: { code: 'permission_unknown', messageKey: 'errors.unknown', httpStatus: 422, action: 'none' },
  audit_filter_invalid: { code: 'audit_filter_invalid', messageKey: 'errors.unknown', httpStatus: 422, action: 'none' },
  timeout: { code: 'timeout', messageKey: 'errors.timeout', httpStatus: 504, action: 'retry' },
  network: { code: 'network', messageKey: 'errors.network', httpStatus: 503, action: 'retry' },
  unknown: { code: 'unknown', messageKey: 'errors.unknown', httpStatus: 500, action: 'retry' },
};

/** Maps any thrown value (Postgres / PostgREST / fetch / our own) to the contract. */
export function toErrorInfo(error: unknown): ErrorInfo {
  const raw = error as { message?: string; code?: string; name?: string } | null | undefined;
  const message = (raw?.message ?? (typeof error === 'string' ? error : '')).trim();
  if (message && ERRORS[message]) return ERRORS[message];
  if (raw?.code && ERRORS[raw.code]) return ERRORS[raw.code];
  if (raw?.code === '42501' || /permission denied/i.test(message)) return ERRORS.permission_denied;
  if (raw?.name === 'AbortError' || /timed? ?out/i.test(message)) return ERRORS.timeout;
  if (/network|fetch failed|failed to fetch/i.test(message)) return ERRORS.network;
  return ERRORS.unknown;
}

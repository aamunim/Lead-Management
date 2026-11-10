// Users / Roles / access explainer / audit calls (0A.18). Every call goes through callWithSessionRetry, so a changed
// access version refreshes the session once; the server is the real check (the screens only hide what you cannot do).
import type { AuditArea, Grants, PermissionInfo, RoleInfo } from './admin-core';
import { callWithSessionRetry, type ErrorInfo } from './errors';
import { supabase } from './supabase';

export type Result<T> = { data: T | null; error: ErrorInfo | null };
export type UserStatus = 'pending' | 'active' | 'deactivated';

export type UserListItem = {
  user_id: string;
  display_name: string | null;
  email: string | null;
  phone: string | null;
  status: UserStatus;
  branch_id: string | null;
  joined_at: string | null;
  deactivated_at: string | null;
  requested_at: string;
  roles: { id: string; name: string | null; name_key: string | null }[];
};
export type UserList = { total: number; counts: Record<UserStatus, number>; items: UserListItem[] };

export type AssignmentState = 'active' | 'scheduled' | 'expired' | 'role_archived';
export type Assignment = {
  id: string;
  role_id: string;
  role_name: string | null;
  role_name_key: string | null;
  is_super_admin: boolean;
  org_unit_id: string | null;
  branch_id: string | null;
  offering_limit: string[] | null;
  valid_from: string;
  valid_to: string | null;
  state: AssignmentState;
};
export type UserDetail = Omit<UserListItem, 'roles'> & {
  is_self: boolean;
  profile_shared: boolean;
  outranks_you: boolean;
  assignments: Assignment[];
  org_units: { id: string; name: string; kind: string; manager: boolean }[];
  permissions: Record<string, string[]>;
  flags: string[];
  call_log_sync_required: boolean | null;
};

export type OrgUnit = { id: string; parent_id: string | null; kind: string; name: string; archived: boolean; branch_id?: string | null };
export type OrgTree = { branches_enabled: boolean; units: OrgUnit[] };

export type ExplainReason = {
  assignment_id: string;
  role_id: string;
  role_name: string | null;
  role_name_key: string | null;
  granted: string | null;
  scope: string | null;
  branch_id: string | null;
  org_unit_id: string | null;
  offering_limit: string[] | null;
  valid_from: string;
  valid_to: string | null;
  verdict: 'allows' | 'blocks' | 'not_relevant';
  rule: string;
  detail: Record<string, unknown>;
};
export type ExplainResult = {
  allowed: boolean;
  summary: 'allowed' | 'membership_inactive' | 'no_roles' | 'no_role_grants' | 'blocked_by_limits';
  permission: string;
  membership_status: UserStatus;
  record: Record<string, unknown>;
  reasons: ExplainReason[];
};
export type RecordRef =
  | { entity: string; id: string; permission?: string }
  | { permission: string; owner_id?: string | null; branch_id?: string | null; offering_id?: string | null; created_by?: string | null };

export type AuditItem = {
  id: string;
  at: string;
  actor_user_id: string | null;
  actor_name: string | null;
  action: string;
  target_type: string;
  target_id: string | null;
  before: Record<string, unknown> | null;
  after: Record<string, unknown> | null;
  reason: string | null;
};
export type AuditFilters = { area?: AuditArea; actor_user_id?: string; from?: string; to?: string; target_id?: string };

const rpc = <T>(where: string, fn: string, args?: Record<string, unknown>): Promise<Result<T>> =>
  callWithSessionRetry<T>(where, async () => {
    const { data, error } = await supabase.rpc(fn, args);
    return { data: data as T | null, error };
  });

// Users
export const fetchUsers = (status: UserStatus | null, search: string) =>
  rpc<UserList>('users.list', 'users_list', { p_status: status, p_search: search.trim() || null, p_limit: 200 });
export const fetchUser = (userId: string) => rpc<UserDetail>('users.detail', 'user_detail', { p_user_id: userId });
export const approveUser = (userId: string) => rpc<null>('users.approve', 'user_approve', { p_user_id: userId });
export const deactivateUser = (userId: string, reason: string) =>
  rpc<null>('users.deactivate', 'user_deactivate', { p_user_id: userId, p_reason: reason.trim() || null });
export const reactivateUser = (userId: string) => rpc<null>('users.reactivate', 'user_reactivate', { p_user_id: userId });
export const updateContact = (userId: string, contact: { name: string; phone: string; email: string }) =>
  rpc<{ display_name: string; phone: string | null; email: string }>('users.contact', 'user_update_contact', {
    p_user_id: userId, p_display_name: contact.name, p_phone: contact.phone || null, p_email: contact.email,
  });

// Assignments
export type AssignmentInput = { userId: string; roleId: string; orgUnitId: string | null; branchId: string | null;
  validFrom: string | null; validTo: string | null; offeringLimit: string[] | null };
export type PreviewRow = { permission: string; scope: string | null; branch_ids: string[] | null; org_unit_id?: string | null; sensitive?: boolean };
export type AssignmentPreview = { current: PreviewRow[]; adds: PreviewRow[] };
export const assignRole = (a: AssignmentInput) => rpc<string>('roles.assign', 'role_assign', {
  p_user_id: a.userId, p_role_id: a.roleId, p_org_unit_id: a.orgUnitId, p_branch_id: a.branchId,
  p_valid_from: a.validFrom, p_valid_to: a.validTo, p_offering_limit: a.offeringLimit,
});
export const previewAssignment = (a: Pick<AssignmentInput, 'userId' | 'roleId' | 'branchId' | 'orgUnitId'>) =>
  rpc<AssignmentPreview>('roles.preview', 'role_assignment_preview', {
    p_user_id: a.userId, p_role_id: a.roleId, p_branch_id: a.branchId, p_org_unit_id: a.orgUnitId,
  });
export const unassignRole = (assignmentId: string) => rpc<null>('roles.unassign', 'role_unassign', { p_assignment_id: assignmentId });

// Roles and the registry
export const fetchRoles = () => rpc<RoleInfo[]>('roles.list', 'roles_get');
export async function fetchRegistry(): Promise<Result<{ permissions: PermissionInfo[]; flags: string[] }>> {
  return callWithSessionRetry('roles.registry', async () => {
    const [perms, flags] = await Promise.all([
      supabase.from('permissions').select('key, module, action, scopable, sensitive, introduced_in_release')
        .eq('kind', 'institution').is('retired_at', null).order('module').order('key'),
      supabase.from('behaviour_flags').select('key').order('key'),
    ]);
    const error = perms.error ?? flags.error;
    if (error) return { data: null, error };
    return { data: { permissions: perms.data as PermissionInfo[], flags: (flags.data as { key: string }[]).map((f) => f.key) }, error: null };
  });
}
export const createRole = (name: string, inheritsFrom: string | null, flags: string[]) =>
  rpc<string>('roles.create', 'role_create', { p_name: name, p_inherits_from_role_id: inheritsFrom, p_flags: flags });
export const updateRole = (roleId: string, name: string | null, flags: string[]) =>
  rpc<null>('roles.update', 'role_update', { p_role_id: roleId, p_name: name, p_flags: flags });
export const setRoleGrants = (roleId: string, grants: Grants) =>
  rpc<Grants>('roles.grants', 'role_set_grants', { p_role_id: roleId, p_grants: grants });
export const copyRole = (roleId: string, name: string) => rpc<string>('roles.copy', 'role_copy', { p_role_id: roleId, p_name: name });
export const deleteRole = (roleId: string, moveTo: string | null) =>
  rpc<null>('roles.delete', 'role_delete', { p_role_id: roleId, p_move_to_role_id: moveTo });

// Organisation (for the branch / unit pickers)
export const fetchOrgTree = () => rpc<OrgTree>('org.tree', 'org_tree_get');

// Access explainer and audit
export const explainAccess = (userId: string, ref: RecordRef) =>
  rpc<ExplainResult>('access.explain', 'access_explain', { p_user_id: userId, p_record_ref: ref });
export const fetchRecordEntities = () =>
  rpc<{ entity: string; permission: string; label_key: string }[]>('access.entities', 'record_entities_get');
export const fetchAudit = (filters: AuditFilters, before?: { at: string; id: string }) =>
  rpc<{ items: AuditItem[]; has_more: boolean }>('audit.list', 'audit_list', {
    p_filters: { ...filters, ...(before ? { before_at: before.at, before_id: before.id } : {}) }, p_limit: 50,
  });

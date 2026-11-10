// Pure helpers for the Users / Roles screens (0A.18). No React, no network: unit-tested in scripts/tests/admin.test.mjs.

export type Scope = 'own' | 'team' | 'org_unit' | 'branch' | 'all';
export const SCOPES: Scope[] = ['own', 'team', 'org_unit', 'branch', 'all'];

/** A grant value as stored by roles_get / role_set_grants: a scope for scopable permissions, true otherwise. */
export type Grant = Scope | true;
export type Grants = Record<string, Grant>;

export type PermissionInfo = {
  key: string;
  module: string;
  action: string;
  scopable: boolean;
  sensitive: boolean;
  introduced_in_release: string;
};

export type RoleInfo = {
  id: string;
  name: string | null;
  name_key: string | null;
  is_system: boolean;
  is_super_admin: boolean;
  template_key: string | null;
  rank: number;
  inherits_from_role_id: string | null;
  flags: string[];
  archived: boolean;
  grants: Grants;
};

/** Translation key of a permission's label / help: "settings.users" → "settings.users.label"; "*" → "all.label". */
export function permissionTextKey(key: string, part: 'label' | 'help'): string {
  return key === '*' ? `all.${part}` : `${key}.${part}`;
}

/** Permissions grouped by module (registry order kept inside a module; modules sorted, "core" first). */
export function groupByModule(permissions: PermissionInfo[]): { module: string; permissions: PermissionInfo[] }[] {
  const groups = new Map<string, PermissionInfo[]>();
  for (const p of permissions) {
    if (p.key === '*') continue;
    const list = groups.get(p.module) ?? [];
    list.push(p);
    groups.set(p.module, list);
  }
  return [...groups.keys()]
    .sort((a, b) => (a === 'core' ? -1 : b === 'core' ? 1 : a.localeCompare(b)))
    .map((module) => ({ module, permissions: groups.get(module)! }));
}

/** Release ids are roadmap milestones ("0A.16", "1A.03"); compares them in delivery order. */
export function compareReleases(a: string, b: string): number {
  const parse = (r: string) => {
    const m = /^(\d+)([A-Z])\.(\d+)$/.exec(r);
    return m ? [Number(m[1]), m[2].charCodeAt(0), Number(m[3])] : null;
  };
  const pa = parse(a);
  const pb = parse(b);
  if (!pa || !pb) return a.localeCompare(b);
  for (let i = 0; i < 3; i += 1) if (pa[i] !== pb[i]) return pa[i] - pb[i];
  return 0;
}

/** "New permissions in this release" (R20): the permissions introduced in the newest release in the registry. */
export function newestRelease(permissions: PermissionInfo[]): { release: string | null; permissions: PermissionInfo[] } {
  const releases = [...new Set(permissions.filter((p) => p.key !== '*').map((p) => p.introduced_in_release))].sort(compareReleases);
  const release = releases.at(-1) ?? null;
  return { release, permissions: permissions.filter((p) => p.key !== '*' && p.introduced_in_release === release) };
}

/** What a role effectively grants for one permission: the Super Admin role has everything. */
export function grantOf(role: Pick<RoleInfo, 'is_super_admin' | 'grants'>, key: string): Grant | null {
  if (role.is_super_admin) return 'all';
  return role.grants[key] ?? null;
}

export type CompareRow = { key: string; a: Grant | null; b: Grant | null; same: boolean };

/** Compare two roles permission by permission; differences first, then the rest in registry order. */
export function compareRoles(a: RoleInfo, b: RoleInfo, permissions: PermissionInfo[]): CompareRow[] {
  const rows = permissions.filter((p) => p.key !== '*').map((p) => {
    const ga = grantOf(a, p.key);
    const gb = grantOf(b, p.key);
    return { key: p.key, a: ga, b: gb, same: ga === gb };
  }).filter((r) => r.a !== null || r.b !== null);
  return [...rows.filter((r) => !r.same), ...rows.filter((r) => r.same)];
}

/** Toggle / rescope one permission in a grants map (never mutates). Scopable permissions start at the narrowest scope. */
export function setGrant(grants: Grants, permission: PermissionInfo, value: Grant | null): Grants {
  const next = { ...grants };
  if (value === null) delete next[permission.key];
  else next[permission.key] = permission.scopable ? (value === true ? 'own' : value) : true;
  return next;
}

/** Grants that differ between two maps (for "unsaved changes" and for warning about sensitive ones). */
export function changedKeys(before: Grants, after: Grants): string[] {
  const keys = new Set([...Object.keys(before), ...Object.keys(after)]);
  return [...keys].filter((k) => before[k] !== after[k]).sort();
}

/** True when a change adds or removes a sensitive permission (the server then needs two-step sign-in). */
export function touchesSensitive(before: Grants, after: Grants, permissions: PermissionInfo[]): boolean {
  const sensitive = new Set(permissions.filter((p) => p.sensitive).map((p) => p.key));
  return changedKeys(before, after).some((k) => sensitive.has(k) && (before[k] === undefined || after[k] === undefined));
}

/** Can the signed-in person use a screen? Mirrors the server's can(key) at any scope ("*" = Super Admin). */
export function hasPermission(permissions: Record<string, unknown> | null | undefined, key: string): boolean {
  if (!permissions) return false;
  return key in permissions || '*' in permissions;
}

/** Search text typed in Bangla digits still matches phone numbers (০১৭… → 017…). */
export function normaliseSearch(text: string): string {
  return text.replace(/[০-৯]/g, (d) => String(d.charCodeAt(0) - 0x09e6)).trim();
}

export type AuditArea = 'all' | 'roles' | 'assignments' | 'users' | 'settings' | 'field_rules';
export const AUDIT_AREAS: AuditArea[] = ['all', 'roles', 'assignments', 'users', 'settings', 'field_rules'];

/** The fields that changed in one audit row, for a short "before → after" line. Secret values are never in the log. */
export function auditChanges(before: Record<string, unknown> | null, after: Record<string, unknown> | null): { field: string; from: string; to: string }[] {
  const show = (v: unknown) => (v === undefined || v === null ? '' : typeof v === 'string' ? v : JSON.stringify(v));
  if (!before || !after || typeof before !== 'object' || typeof after !== 'object') return [];
  const keys = [...new Set([...Object.keys(before), ...Object.keys(after)])].sort();
  return keys.filter((k) => show(before[k]) !== show(after[k])).map((k) => ({ field: k, from: show(before[k]), to: show(after[k]) }));
}

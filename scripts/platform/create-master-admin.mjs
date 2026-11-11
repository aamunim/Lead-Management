// First Master Admin (0B.02-T8): command line only, never a public page. Run against the target database:
//   DB_URL=… ADMIN_EMAIL=you@example.com ADMIN_PASSWORD='a long password' node scripts/platform/create-master-admin.mjs
// Creates the sign-in account if it does not exist (email confirmed), makes it a Master Admin and writes the platform
// audit log. The person then signs in at /panel/sign-in and must set up an authenticator (second step) before anything
// works. Refuses if an active Master Admin already exists, unless FORCE=1 (e.g. recovering a lost account).
import { execFileSync } from 'node:child_process';

const db = process.env.DB_URL;
const email = (process.env.ADMIN_EMAIL ?? '').trim().toLowerCase();
const password = process.env.ADMIN_PASSWORD ?? '';
if (!db || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
  console.error('Set DB_URL and ADMIN_EMAIL (and ADMIN_PASSWORD for a new account).');
  process.exit(1);
}
const psql = (sql, vars = {}) => execFileSync('psql', [db, '-X', '-q', '-A', '-t', '-v', 'ON_ERROR_STOP=1',
  ...Object.entries(vars).flatMap(([k, v]) => ['-v', `${k}=${v}`])], { input: sql, encoding: 'utf8' }).trim();

const existing = Number(psql("select count(*) from public.platform_members where platform_role = 'master_admin' and status = 'active';"));
if (existing > 0 && process.env.FORCE !== '1') {
  console.error('An active Master Admin already exists: invite more from the panel (Platform users). FORCE=1 to override.');
  process.exit(1);
}
const userExists = psql("select count(*) from auth.users where lower(email) = :'email';", { email }) !== '0';
if (!userExists && password.length < 14) {
  console.error('A new account needs ADMIN_PASSWORD of at least 14 characters.');
  process.exit(1);
}
psql(`
begin;
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
                        created_at, updated_at, confirmation_token, recovery_token, email_change_token_new, email_change)
select '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated', :'email',
       extensions.crypt(:'password', extensions.gen_salt('bf')), now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', ''
 where not exists (select 1 from auth.users where lower(email) = :'email');
insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
select u.id, u.id, u.id::text, jsonb_build_object('sub', u.id, 'email', u.email, 'email_verified', true), 'email', now(), now(), now()
  from auth.users u where lower(u.email) = :'email' and not exists (select 1 from auth.identities i where i.user_id = u.id);
insert into public.platform_members (user_id, platform_role)
select id, 'master_admin' from auth.users where lower(email) = :'email'
on conflict (user_id) do update set platform_role = 'master_admin', status = 'active';
insert into public.platform_audit_log (actor_user_id, action, target_type, target_id, after, reason)
select null, 'platform_user.seeded', 'platform_user', id::text, jsonb_build_object('platform_role', 'master_admin'), 'command line (0B.02-T8)'
  from auth.users where lower(email) = :'email';
commit;`, { email, password: password || 'unused-existing-account' });
console.log(`${email} is a Master Admin. Sign in at /panel/sign-in and set up the authenticator (second step).`);

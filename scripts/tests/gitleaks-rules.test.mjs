// The custom secret-scan rules (0B.11-T10) catch the provider credential formats and leave normal code alone.
// gitleaks uses Go (RE2) regular expressions; these rules use only syntax JavaScript reads the same way, except the
// leading (?i), which becomes the "i" flag here.
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { describe, it } from 'node:test';

const toml = readFileSync(new URL('../../.gitleaks.toml', import.meta.url), 'utf8');
const rules = Object.fromEntries([...toml.matchAll(/id = "([^"]+)"[\s\S]*?regex = '''(.*?)'''/g)].map(([, id, re]) => {
  const insensitive = re.startsWith('(?i)');
  return [id, new RegExp(insensitive ? re.slice(4) : re, insensitive ? 'i' : '')];
}));
// Made-up values, assembled at run time so this file itself holds no credential-looking literal.
const fake = (prefix, n) => prefix + 'x9Q2'.repeat(Math.ceil(n / 4)).slice(0, n);

describe('secret-scan rules', () => {
  it('has the provider rules and keeps the defaults', () => {
    assert.match(toml, /useDefault = true/);
    for (const id of ['sslcommerz-store-password', 'sms-gateway-api-key', 'google-oauth-refresh-token', 'smtp-password']) assert.ok(rules[id], id);
  });
  it('catches the formats', () => {
    assert.match(`store_passwd = "${fake('Ab', 12)}@ssl"`, rules['sslcommerz-store-password']);
    assert.match(`SMS_API_KEY: '${fake('', 24)}'`, rules['sms-gateway-api-key']);
    assert.match(`refresh: ${fake('1//0', 50)}`, rules['google-oauth-refresh-token']);
    assert.match(`smtpPassword = "${fake('p', 14)}"`, rules['smtp-password']);
  });
  it('does not flag normal code', () => {
    assert.doesNotMatch("secret_fields: '{store_password}'", rules['sslcommerz-store-password']);
    assert.doesNotMatch("t('integrations.secretValue')", rules['sms-gateway-api-key']);
    assert.doesNotMatch('kind: sms, sender_id: ACME', rules['sms-gateway-api-key']);
    assert.doesNotMatch("label: 'SMTP mail server'", rules['smtp-password']);
  });
});

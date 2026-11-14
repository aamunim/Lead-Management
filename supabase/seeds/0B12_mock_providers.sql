-- 0B.12 mock adapters (engineering only; local and CI seeds, never staging or production): providers the hub tests
-- and the worker's unit tests use. The mock SMS gateway fails a send whose body contains "FAIL" (adapter error) or
-- "BALANCE" (balance low, the institution's side).
insert into public.integration_providers (key, kind, name, settings_schema, secret_fields, capabilities, adapter_version, status, sort) values
  ('mock_sms', 'sms', '{"en":"Mock SMS (tests)","bn":"মক SMS (টেস্ট)"}',
   '{"type":"object","additionalProperties":false,"properties":{"price_per_part":{"type":"number","minimum":0},"rate_per_minute":{"type":"integer","minimum":1},"sender_id":{"type":"string","maxLength":20}}}',
   '{api_key,webhook_secret}', '{send,bulk,unicode,status}', 'mock-1', 'beta', 900),
  ('mock_email', 'email', '{"en":"Mock email (tests)","bn":"মক ইমেইল (টেস্ট)"}',
   '{"type":"object","additionalProperties":false,"properties":{"price_per_part":{"type":"number","minimum":0},"from_email":{"type":"string"}}}',
   '{api_key}', '{send}', 'mock-1', 'beta', 910)
on conflict (key) do nothing;

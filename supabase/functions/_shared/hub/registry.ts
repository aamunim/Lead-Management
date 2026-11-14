// Adapter registry (0B.12-T2): provider key → adapter. Real adapters register here as they ship (0B.13 SMS,
// 0B.14 email). The mock adapters are registered only when HUB_ALLOW_MOCK is set (local and CI, never production).
import type { Adapter } from './adapters.ts';
import { mockEmail, mockSms } from './mock.ts';

export function adapterRegistry(allowMock: boolean): Record<string, Adapter> {
  const real: Record<string, Adapter> = {};
  return allowMock ? { ...real, mock_sms: mockSms, mock_email: mockEmail } : real;
}

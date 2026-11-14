// Adapter registry (0B.12-T2): provider key → adapter. Real adapters register here as they ship (0B.13 Custom HTTP;
// the ready-made Bangladeshi gateways once the owner confirms the shortlist; 0B.14 SMTP and Resend). The mock adapters are
// registered only when HUB_ALLOW_MOCK is set (local and CI, never production).
import type { Adapter } from './adapters.ts';
import { customHttpAdapter } from './custom-http.ts';
import { mockEmail, mockSms } from './mock.ts';
import { resendAdapter } from './resend.ts';
import { smtpAdapter, type SmtpOpener } from './smtp.ts';

export function adapterRegistry(allowMock: boolean, resolve?: (host: string) => Promise<string[]>, openSmtp?: SmtpOpener)
  : Record<string, Adapter> {
  const real: Record<string, Adapter> = { custom_http_sms: customHttpAdapter(resolve), resend: resendAdapter };
  if (openSmtp) real.smtp = smtpAdapter(openSmtp);
  return allowMock ? { ...real, mock_sms: mockSms, mock_email: mockEmail } : real;
}

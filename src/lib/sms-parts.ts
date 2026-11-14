// SMS parts for the app (0B.13-T5): the same rule as the hub (supabase/functions/_shared/hub/sms-parts.ts) and the
// database (app.sms_parts) — a unit test keeps the three in step. Plain text 160 / 153, Bangla (Unicode) 70 / 67.
const GSM7 = /^[A-Za-z0-9 @£$¥èéùìòÇØøÅå_^{}\[~\]|€ÆæßÉ!"#¤%&'()*+,\-./:;<=>?¡ÄÖÑÜ§¿äöñüà\n\r]*$/;

export function smsParts(text: string): { parts: number; unicode: boolean; length: number } {
  const length = [...text].length;
  const unicode = !GSM7.test(text);
  const [single, multi] = unicode ? [70, 67] : [160, 153];
  return { parts: length <= single ? 1 : Math.ceil(length / multi), unicode, length };
}

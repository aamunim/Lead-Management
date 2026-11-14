// SMS parts (0B.13-T5; Ch 9.7): GSM-7 text 160 characters (153 per part when split), anything else — Bangla — is
// Unicode at 70 (67). The same rule as app.sms_parts in the database; the app shows parts and cost before sending.
const GSM7 = /^[A-Za-z0-9 @£$¥èéùìòÇØøÅå_^{}\[~\]|€ÆæßÉ!"#¤%&'()*+,\-./:;<=>?¡ÄÖÑÜ§¿äöñüà\n\r]*$/;

export function smsParts(text: string): { parts: number; unicode: boolean; length: number } {
  const length = [...text].length;
  const unicode = !GSM7.test(text);
  const [single, multi] = unicode ? [70, 67] : [160, 153];
  return { parts: length <= single ? 1 : Math.ceil(length / multi), unicode, length };
}

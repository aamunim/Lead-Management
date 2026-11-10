// Typography tokens (0A.13-T3). Pure: unit-tested in Node.
// Bangla vowel signs above and below the line (ি ী ু ূ ৃ, রেফ) are clipped when the line height is tight, so Bangla
// text gets a taller line (1.6×) than Latin text (1.35–1.45×). Sizes follow the phone's font-size setting (fontScale);
// layouts must grow with the text (never a fixed height around text).

import { BANGLA_FONT_FAMILY } from '../../i18n/language.ts';

export type TypeRole = 'display' | 'headline' | 'title' | 'titleSmall' | 'body' | 'bodySmall' | 'label' | 'caption';
export type TextStyleToken = { fontSize: number; lineHeight: number; fontWeight: '400' | '600'; fontFamily?: string };

const SCALE: Record<TypeRole, { size: number; weight: '400' | '600'; latin: number }> = {
  display: { size: 32, weight: '600', latin: 1.25 },
  headline: { size: 24, weight: '600', latin: 1.3 },
  title: { size: 20, weight: '600', latin: 1.35 },
  titleSmall: { size: 17, weight: '600', latin: 1.4 },
  body: { size: 16, weight: '400', latin: 1.45 },
  bodySmall: { size: 14, weight: '400', latin: 1.45 },
  label: { size: 15, weight: '600', latin: 1.35 },
  caption: { size: 13, weight: '400', latin: 1.4 },
};
export const BANGLA_LINE_HEIGHT = 1.6;
export const MAX_FONT_SCALE = 2; // beyond this, layouts on 5-inch phones cannot work; Android's largest is ~2.0

export function typeScale(language: string, fontScale = 1): Record<TypeRole, TextStyleToken> {
  const bn = language === 'bn';
  const scale = Math.min(Math.max(fontScale, 0.85), MAX_FONT_SCALE);
  const out = {} as Record<TypeRole, TextStyleToken>;
  for (const [role, s] of Object.entries(SCALE) as [TypeRole, (typeof SCALE)[TypeRole]][]) {
    const fontSize = Math.round(s.size * scale);
    out[role] = {
      fontSize,
      lineHeight: Math.ceil(fontSize * (bn ? BANGLA_LINE_HEIGHT : s.latin)),
      fontWeight: s.weight,
      ...(bn ? { fontFamily: BANGLA_FONT_FAMILY } : {}),
    };
  }
  return out;
}

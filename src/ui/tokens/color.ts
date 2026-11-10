// Colour tokens (0A.13-T1/T2). Pure: unit-tested in Node (scripts/tests/design.test.mjs).
// Palettes are generated from one brand colour as tonal steps in OKLCH (perceptually even), Material 3 style:
// tone 0 = black … tone 100 = white. Roles (primary, surface, …) pick tones per light / dark mode, and every
// text/background pair is checked against WCAG contrast (4.5:1 for text, 3:1 for large text and UI outlines).

export const DEFAULT_BRAND = '#3557D4'; // platform brand blue (Ch 47.2); institutions override it (0B branding)

type Rgb = { r: number; g: number; b: number }; // 0..1
type Oklch = { l: number; c: number; h: number };

export function parseHex(hex: string): Rgb | null {
  const m = /^#?([0-9a-f]{6})$/i.exec(hex.trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return { r: ((n >> 16) & 255) / 255, g: ((n >> 8) & 255) / 255, b: (n & 255) / 255 };
}

export function toHex({ r, g, b }: Rgb): string {
  const c = (v: number) => Math.round(Math.min(1, Math.max(0, v)) * 255).toString(16).padStart(2, '0');
  return `#${c(r)}${c(g)}${c(b)}`.toUpperCase();
}

const lin = (v: number) => (v <= 0.04045 ? v / 12.92 : ((v + 0.055) / 1.055) ** 2.4);
const gam = (v: number) => (v <= 0.0031308 ? 12.92 * v : 1.055 * v ** (1 / 2.4) - 0.055);

function rgbToOklch(rgb: Rgb): Oklch {
  const r = lin(rgb.r); const g = lin(rgb.g); const b = lin(rgb.b);
  const l = Math.cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b);
  const m = Math.cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b);
  const s = Math.cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b);
  const L = 0.2104542553 * l + 0.793617785 * m - 0.0040720468 * s;
  const A = 1.9779984951 * l - 2.428592205 * m + 0.4505937099 * s;
  const B = 0.0259040371 * l + 0.7827717662 * m - 0.808675766 * s;
  return { l: L, c: Math.hypot(A, B), h: (Math.atan2(B, A) * 180) / Math.PI };
}

function oklchToRgb({ l: L, c, h }: Oklch): Rgb {
  const A = c * Math.cos((h * Math.PI) / 180);
  const B = c * Math.sin((h * Math.PI) / 180);
  const l = (L + 0.3963377774 * A + 0.2158037573 * B) ** 3;
  const m = (L - 0.1055613458 * A - 0.0638541728 * B) ** 3;
  const s = (L - 0.0894841775 * A - 1.291485548 * B) ** 3;
  return {
    r: gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
    g: gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
    b: gam(-0.0041960863 * l - 0.7034186147 * m + 1.707614701 * s),
  };
}

const inGamut = (c: Rgb) => [c.r, c.g, c.b].every((v) => v >= -0.0001 && v <= 1.0001);

/** Colour of a hue/chroma at a tone (0–100), reducing chroma until it fits sRGB. */
export function tone(base: string, t: number, chromaScale = 1): string {
  const rgb = parseHex(base) ?? parseHex(DEFAULT_BRAND)!;
  const { c, h } = rgbToOklch(rgb);
  let chroma = c * chromaScale;
  const l = Math.min(1, Math.max(0, t / 100));
  let out = oklchToRgb({ l, c: chroma, h });
  for (let i = 0; i < 40 && !inGamut(out); i += 1) {
    chroma *= 0.9;
    out = oklchToRgb({ l, c: chroma, h });
  }
  return toHex(out);
}

// ---------------------------------------------------------------------------------------------------------------------
// Contrast (WCAG 2.x)
// ---------------------------------------------------------------------------------------------------------------------
export function luminance(hex: string): number {
  const c = parseHex(hex);
  if (!c) return 0;
  return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b);
}

export function contrastRatio(a: string, b: string): number {
  const [x, y] = [luminance(a), luminance(b)].sort((p, q) => q - p);
  return (x + 0.05) / (y + 0.05);
}

export const AA_TEXT = 4.5;
export const AA_LARGE = 3;

/** The tone of `base` closest to `startTone` that reaches `min` contrast on `background`. */
export function safeTone(base: string, background: string, min: number, startTone: number): string {
  const darker = luminance(background) > 0.18; // light background → search darker tones
  for (let t = startTone; t >= 0 && t <= 100; t += darker ? -2 : 2) {
    const candidate = tone(base, t);
    if (contrastRatio(candidate, background) >= min) return candidate;
  }
  return darker ? '#000000' : '#FFFFFF';
}

export type BrandCheck = {
  brand: string;
  /** The brand colour itself can carry white/black text (buttons) and be read as text on the surface. */
  usableAsPrimary: boolean;
  onBrandText: string;
  ratioOnBrand: number;
  ratioAsText: number;
};

/** Contrast check of an institution colour in one mode (0A.13-T2, Ch 47.12 #2). */
export function checkBrand(brand: string, mode: 'light' | 'dark'): BrandCheck {
  const valid = parseHex(brand) ? brand.toUpperCase() : DEFAULT_BRAND;
  const surface = mode === 'light' ? tone(valid, 98, 0.04) : tone(valid, 6, 0.04);
  const onBrandText = contrastRatio('#FFFFFF', valid) >= contrastRatio('#000000', valid) ? '#FFFFFF' : '#000000';
  const ratioOnBrand = contrastRatio(onBrandText, valid);
  const ratioAsText = contrastRatio(valid, surface);
  return { brand: valid, usableAsPrimary: ratioOnBrand >= AA_TEXT && ratioAsText >= AA_TEXT, onBrandText, ratioOnBrand, ratioAsText };
}

// ---------------------------------------------------------------------------------------------------------------------
// Roles
// ---------------------------------------------------------------------------------------------------------------------
export type Temperature = 'hot' | 'warm' | 'cold';
const TEMPERATURE_HUES: Record<Temperature, string> = { hot: '#D93A1F', warm: '#C77700', cold: '#1F6FD9' };
const ERROR = '#BA1A1A';
const SUCCESS = '#2E7D32';

export type ColorRoles = {
  mode: 'light' | 'dark';
  brand: string;
  brandAccentOnly: boolean; // true: the institution colour failed contrast and is used for accents only
  accent: string; // the institution colour as given (stripes, small marks; never text)
  primary: string; onPrimary: string; primaryContainer: string; onPrimaryContainer: string;
  background: string; surface: string; surfaceContainerLow: string; surfaceContainer: string; surfaceContainerHigh: string;
  onSurface: string; onSurfaceVariant: string; outline: string; outlineVariant: string;
  inverseSurface: string; inverseOnSurface: string; inversePrimary: string; scrim: string;
  error: string; onError: string; errorContainer: string; onErrorContainer: string;
  success: string; onSuccessContainer: string; successContainer: string;
  hot: string; hotContainer: string; onHotContainer: string;
  warm: string; warmContainer: string; onWarmContainer: string;
  cold: string; coldContainer: string; onColdContainer: string;
};

export function colorRoles(brandInput: string | null | undefined, mode: 'light' | 'dark'): ColorRoles {
  const check = checkBrand(brandInput ?? DEFAULT_BRAND, mode);
  const b = check.brand;
  const L = mode === 'light';
  const n = (t: number) => tone(b, t, 0.06); // neutral: brand hue, very low chroma
  const nv = (t: number) => tone(b, t, 0.15); // neutral variant
  const surface = L ? n(98) : n(6);
  // D12: use the institution colour itself when it is readable; otherwise a safe tone of its hue (accent stays).
  const primary = L && check.usableAsPrimary ? b : safeTone(b, surface, AA_TEXT, L ? 40 : 80);
  const onPrimary = contrastRatio('#FFFFFF', primary) >= contrastRatio('#000000', primary) ? '#FFFFFF' : (L ? tone(b, 10) : tone(b, 20));
  const temp = (k: Temperature) => ({
    main: safeTone(TEMPERATURE_HUES[k], surface, AA_TEXT, L ? 45 : 80),
    container: tone(TEMPERATURE_HUES[k], L ? 92 : 30),
    on: tone(TEMPERATURE_HUES[k], L ? 15 : 92),
  });
  const hot = temp('hot'); const warm = temp('warm'); const cold = temp('cold');
  return {
    mode, brand: b, brandAccentOnly: !(L ? check.usableAsPrimary : contrastRatio(b, surface) >= AA_TEXT), accent: b,
    primary, onPrimary,
    primaryContainer: L ? tone(b, 90) : tone(b, 30), onPrimaryContainer: L ? tone(b, 10) : tone(b, 90),
    background: surface, surface,
    surfaceContainerLow: L ? n(96) : n(10), surfaceContainer: L ? n(94) : n(12), surfaceContainerHigh: L ? n(92) : n(17),
    onSurface: L ? n(10) : n(90), onSurfaceVariant: L ? nv(30) : nv(80),
    outline: L ? nv(50) : nv(60), outlineVariant: L ? nv(80) : nv(30),
    inverseSurface: L ? n(20) : n(90), inverseOnSurface: L ? n(95) : n(20),
    inversePrimary: safeTone(b, L ? n(20) : n(90), AA_TEXT, L ? 80 : 40), // snackbar action on the inverse surface
    scrim: '#000000',
    error: L ? tone(ERROR, 40) : tone(ERROR, 80), onError: L ? '#FFFFFF' : tone(ERROR, 20),
    errorContainer: L ? tone(ERROR, 90) : tone(ERROR, 30), onErrorContainer: L ? tone(ERROR, 10) : tone(ERROR, 90),
    success: safeTone(SUCCESS, surface, AA_TEXT, L ? 40 : 80),
    successContainer: L ? tone(SUCCESS, 90) : tone(SUCCESS, 30), onSuccessContainer: L ? tone(SUCCESS, 10) : tone(SUCCESS, 90),
    hot: hot.main, hotContainer: hot.container, onHotContainer: hot.on,
    warm: warm.main, warmContainer: warm.container, onWarmContainer: warm.on,
    cold: cold.main, coldContainer: cold.container, onColdContainer: cold.on,
  };
}

/** Text/background pairs that must meet AA (checked by unit tests for any brand colour, Ch 47.12 #1). */
export const TEXT_PAIRS: [keyof ColorRoles, keyof ColorRoles, number][] = [
  ['onSurface', 'surface', AA_TEXT], ['onSurfaceVariant', 'surface', AA_TEXT], ['onSurface', 'surfaceContainerHigh', AA_TEXT],
  ['primary', 'surface', AA_TEXT], ['onPrimary', 'primary', AA_TEXT], ['onPrimaryContainer', 'primaryContainer', AA_TEXT],
  ['error', 'surface', AA_TEXT], ['onError', 'error', AA_TEXT], ['onErrorContainer', 'errorContainer', AA_TEXT],
  ['inverseOnSurface', 'inverseSurface', AA_TEXT], ['inversePrimary', 'inverseSurface', AA_LARGE],
  ['success', 'surface', AA_TEXT], ['onSuccessContainer', 'successContainer', AA_TEXT],
  ['hot', 'surface', AA_TEXT], ['onHotContainer', 'hotContainer', AA_TEXT],
  ['warm', 'surface', AA_TEXT], ['onWarmContainer', 'warmContainer', AA_TEXT],
  ['cold', 'surface', AA_TEXT], ['onColdContainer', 'coldContainer', AA_TEXT],
  ['outline', 'surface', AA_LARGE],
];

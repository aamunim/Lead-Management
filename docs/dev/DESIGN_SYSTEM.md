# Design system: tokens, theme and components (0A.13)

Plan: Ch 47 (47.2–47.5, 47.8, 47.11, 47.12), Ch 13.4. Decisions D12, D13. Code: `src/ui/` (tokens, theme,
components). Gallery: `/dev/gallery` (developers only). Harness: `scripts/ui/gallery.web.test.mjs`.

**Every screen is built from `@/ui` components and `useTheme()` tokens.** That is how dark mode, the institution's
colour, Bangla text and large fonts work everywhere without anyone remembering to.

## Tokens (`src/ui/tokens/`)

| File | What |
|---|---|
| `color.ts` | Tonal palettes from one brand colour (OKLCH), roles for light and dark (Material 3 names: `primary`, `onPrimary`, `primaryContainer`, `surface`, `surfaceContainer*`, `onSurface`, `outline`, `inverseSurface`, `error*`, `success*`), hot / warm / cold, WCAG contrast functions |
| `type.ts` | Type scale (`headline`, `title`, `titleSmall`, `body`, `bodySmall`, `label`, `caption`); **Bangla line height 1.6×** so vowel signs (ি ী ু ূ ৃ) are never clipped; follows the phone's font size up to 2× |
| `layout.ts` | Spacing (4-point grid), radius, `TOUCH` = 48 dp, readable max width |

Default brand: platform blue `#3557D4`. The institution's colour comes from branding settings (0B, Ch 6); the theme
reads the setting `brand_color` once it exists.

### Brand colour contrast (Ch 47.12 #2)

`checkBrand()` tests the colour against white/black text and against the surface. If it fails (e.g. light yellow
`#FFF59D`), the colour is kept as `accent` (stripes, small marks; never text) and `primary` becomes the nearest tone
of the same hue that reaches 4.5:1. Unit tests check every text/background role pair for eleven brand colours, light
and dark (`scripts/tests/design.test.mjs`).

## Theme (`src/ui/theme.tsx`)

- `ThemeProvider` (in the root layout) and `useTheme()` → `{ mode, appearance, colors, type, space, radius, touch, fontScale }`.
- Appearance **System / Light / Dark** (screen `/appearance`), saved on the device, applied **at once, without a
  restart** (the old app restarted, Ch 47.2). React Navigation and the system background follow the theme.
- `setThemePreview({ brand, fontScale })`: developer previews only (gallery, screenshot tests).

## Components (`src/ui/components`)

| Component | Notes |
|---|---|
| `Button` (filled, tonal, outlined, text, danger), `IconButton` | ≥ 48 × 48; label read by screen readers (required on `IconButton`); busy state blocks a second press |
| `TextField` (text, name, email, number, decimal, password, otp, search, multiline) | Right keyboard per kind; error right under the field; **Next** moves to the next field, **Done** on the `last` field runs `onDone`; OTP autofill (Android SMS, iOS / web one-time code) |
| `PhoneInput`, `AmountInput` (`src/components/fields`) | Bangla digits → ASCII while typing; lakh display; same Field shell |
| `DateField`, `DateTimeField` | Institution time zone and week start; bn / en |
| `FormScreen` + `useDraft`, `useSubmit`, `useUnsavedChangesPrompt` | Focused field above the keyboard; **Save bar above the keyboard**; scroll / tap outside closes the keyboard; Back asks "Discard changes?"; draft saved while typing and on background (survives a call or app kill); `useSubmit` blocks double submit and gives an **idempotency key** that stays the same for retries — send it to the RPC (`p_idempotency_key`) |
| `BottomSheet` | Scrolls the focused field above the keyboard; optional footer (Save); Back / outside tap closes |
| `Skeleton`, `EmptyState`, `ErrorState`, `StateList`, `ProgressTask` | Loading never blank; empty with an action (label-aware text); error with the translated message and Retry; pull-to-refresh; progress % + Cancel |
| `useSnackbar().showUndo(text, undo)` | Undo after delete; above keyboard and system bar; announced |
| `useConfirm()` | Confirmation dialog (`danger` style for destructive actions) |
| `ChoiceList`, `TemperatureChip`, `Screen`, `Field` | Radio list; hot / warm / cold with icon + word (never colour alone); safe-area screen; label / help / error shell |
| `AppText variant=…` | Text with the language's font and the token's size and line height |

Keyboard handling uses `react-native-keyboard-controller` (in the SDK 58 bundled modules; Android needs a
development or preview build, not Expo Go). On the web it falls back to normal scrolling.

## Checks that run automatically

| Check | Where |
|---|---|
| Role on every Pressable, label on every IconButton, no raw `fontSize` / `lineHeight` outside `src/ui`, no raw colours outside `src/ui/tokens` | `npm run check:i18n` (UI lint) |
| Every role pair meets WCAG AA for many brand colours | `npm test` (`design.test.mjs`) |
| Gallery in light / dark × bn / en, weird labels, font 1.8×, yellow brand: contrast of every text, Bangla line height ≥ 1.5×, nothing off screen, targets ≥ 48 px; screenshots uploaded by CI | `npm run test:ui` (`gallery.web.test.mjs`) |
| Instant theme switch, undo, dialog, sheet, double submit, draft after reload, Back prompt | `npm run test:ui` |
| Android: long form on a small screen keeps the field and Save above the keyboard | `.maestro/long-form-keyboard.yaml` (needs a device / emulator and a preview build; not run in CI yet) |

The manual part is the **per-screen checklist in the PR template** (Ch 47.11).

## Not covered yet

- Real low-end phone runs (owner checkpoint after the first preview build, 0A.14).
- Navigation rules (Android Back from Home, keeping the list position) come with the app shell and the first lists.
- Brand colour from institution branding settings: 0B (Ch 6).

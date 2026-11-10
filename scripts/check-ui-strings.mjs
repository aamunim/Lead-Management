// Hard-coded UI string lint (0A.10-T4). Parses every .ts/.tsx file under src/ with the TypeScript compiler and fails on:
// - JSX text that contains letters:                 <Text>Save</Text>
// - string literals in JSX children:                <Text>{'Save'}</Text>, <Text>{`Hi ${name}`}</Text>
// - literals in user-visible props:                 title="…", placeholder="…", accessibilityLabel="…" …
// - literals in navigation options / alerts:        options={{ title: '…' }}, Alert.alert('…')
// - renamable terms anywhere in string literals:    'Student', 'শিক্ষার্থী' … (they come from labels, 0A.12)
// - toLocaleString / toLocaleDateString / Intl.* outside src/lib/format.ts (lakh grouping, time zone, digits; 0A.11)
// - the phone clock (Date.now(), new Date() without arguments) outside src/lib/server-time.ts (Ch 47.7)
// Design system (0A.13, Ch 47.8 / 47.11):
// - Pressable / Touchable* without accessibilityRole; IconButton without label (screen readers)
// - fontSize / lineHeight outside src/ui/ (use <AppText variant=…>: Bangla-safe line height, follows font size)
// - colour literals (#hex, rgb()) outside src/ui/tokens/ (use useTheme().colors: light / dark / brand)
// Exemption: a comment `i18n-exempt: <reason>` on the same or the previous line; for a developer-only file,
// `i18n-exempt-file: <reason>` anywhere in it.
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

import { FORBIDDEN_TERMS } from './check-translations.mjs';

export const VISIBLE_PROPS = new Set([
  'title', 'placeholder', 'label', 'accessibilityLabel', 'accessibilityHint', 'aria-label', 'alt', 'headerTitle',
  'headerBackTitle', 'tabBarLabel', 'drawerLabel', 'subtitle', 'description', 'message', 'helperText', 'errorText',
]);
const PRESSABLES = new Set(['Pressable', 'TouchableOpacity', 'TouchableHighlight', 'TouchableWithoutFeedback']);
const TYPE_PROPS = new Set(['fontSize', 'lineHeight']);
const FORMAT_FILE = 'src/lib/format.ts';
const CLOCK_FILE = 'src/lib/server-time.ts';
const LOCALE_METHODS = new Set(['toLocaleString', 'toLocaleDateString', 'toLocaleTimeString', 'toLocaleUpperCase', 'toLocaleLowerCase']);
const ALERT_CALLS = new Set(['Alert.alert', 'Alert.prompt', 'alert', 'confirm', 'prompt', 'Toast.show']);
const hasLetters = (text) => /\p{L}/u.test(text);

function exempt(sourceText, lines, node, sourceFile) {
  const line = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line;
  return [lines[line], lines[line - 1]].some((l) => l && /i18n-exempt:\s*\S/.test(l));
}

/** @returns {{ file: string, line: number, rule: string, text: string }[]} */
export function checkSource(fileName, sourceText) {
  if (/i18n-exempt-file:\s*\S/.test(sourceText)) return [];
  const sourceFile = ts.createSourceFile(fileName, sourceText, ts.ScriptTarget.Latest, true,
    fileName.endsWith('.tsx') ? ts.ScriptKind.TSX : ts.ScriptKind.TS);
  const lines = sourceText.split('\n');
  const findings = [];
  const report = (node, rule, text) => {
    if (exempt(sourceText, lines, node, sourceFile)) return;
    const line = sourceFile.getLineAndCharacterOfPosition(node.getStart(sourceFile)).line + 1;
    findings.push({ file: fileName, line, rule, text: String(text).trim().slice(0, 60) });
  };
  const literalText = (node) => {
    if (!node) return null;
    if (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) return node.text;
    if (ts.isTemplateExpression(node)) return [node.head.text, ...node.templateSpans.map((s) => s.literal.text)].join(' ');
    if (ts.isParenthesizedExpression(node)) return literalText(node.expression);
    if (ts.isConditionalExpression(node)) {
      return [literalText(node.whenTrue), literalText(node.whenFalse)].filter((x) => x !== null).join(' ') || null;
    }
    if (ts.isBinaryExpression(node) && node.operatorToken.kind === ts.SyntaxKind.PlusToken) {
      return [literalText(node.left), literalText(node.right)].filter((x) => x !== null).join(' ') || null;
    }
    return null;
  };
  const isImportOrTypeContext = (node) =>
    ts.isImportDeclaration(node.parent) || ts.isExportDeclaration(node.parent) || ts.isLiteralTypeNode(node.parent) ||
    ts.isExternalModuleReference(node.parent);

  const file = fileName.replace(/\\/g, '/');
  const inUi = file.startsWith('src/ui/');
  const inTokens = file.startsWith('src/ui/tokens/');
  const visit = (node) => {
    if (ts.isJsxOpeningElement(node) || ts.isJsxSelfClosingElement(node)) {
      const tag = node.tagName.getText(sourceFile);
      const attrs = new Set(node.attributes.properties.filter(ts.isJsxAttribute).map((a) => a.name.getText(sourceFile)));
      const spreads = node.attributes.properties.some(ts.isJsxSpreadAttribute);
      if (PRESSABLES.has(tag) && !attrs.has('accessibilityRole') && !attrs.has('role') && !spreads) {
        report(node, 'a11y_role', `<${tag}> needs accessibilityRole (or use Button / IconButton from '@/ui/components')`);
      }
      if (tag === 'IconButton' && !attrs.has('label') && !spreads) report(node, 'a11y_label', '<IconButton> needs a label');
    }
    if (!inUi && ts.isPropertyAssignment(node) && TYPE_PROPS.has(node.name.getText(sourceFile))) {
      report(node, 'raw_font_size', `${node.name.getText(sourceFile)}: use <AppText variant=…> (typography tokens)`);
    }
    if (!inTokens && (ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node))
        && /^(#[0-9a-f]{3,8}|rgba?\(.*\)|hsla?\(.*\))$/i.test(node.text.trim())) {
      report(node, 'raw_color', `${node.text}: use useTheme().colors`);
    }
    if (file !== FORMAT_FILE) {
      if (ts.isPropertyAccessExpression(node) && LOCALE_METHODS.has(node.name.text)) {
        report(node, 'raw_locale_format', `${node.name.text}: use the formatters from '@/lib/locale' (useFormat)`);
      }
      if (ts.isPropertyAccessExpression(node) && ts.isIdentifier(node.expression) && node.expression.text === 'Intl') {
        report(node, 'raw_locale_format', `Intl.${node.name.text}: use '@/lib/format'`);
      }
    }
    if (file !== CLOCK_FILE) {
      if (ts.isCallExpression(node) && node.expression.getText(sourceFile) === 'Date.now') {
        report(node, 'phone_clock', 'Date.now(): use serverNow() from @/lib/server-time');
      }
      if (ts.isNewExpression(node) && node.expression.getText(sourceFile) === 'Date' && (!node.arguments || node.arguments.length === 0)) {
        report(node, 'phone_clock', 'new Date(): use serverNow() from @/lib/server-time');
      }
    }
    if (ts.isJsxText(node) && hasLetters(node.text)) report(node, 'jsx_text', node.text);
    if (ts.isJsxExpression(node) && node.expression && (ts.isJsxElement(node.parent) || ts.isJsxFragment(node.parent))) {
      const text = literalText(node.expression);
      if (text !== null && hasLetters(text)) report(node, 'jsx_literal', text);
    }
    if (ts.isJsxAttribute(node) && VISIBLE_PROPS.has(node.name.getText(sourceFile)) && node.initializer) {
      const init = ts.isJsxExpression(node.initializer) ? node.initializer.expression : node.initializer;
      const text = literalText(init);
      if (text !== null && hasLetters(text)) report(node, 'visible_prop', `${node.name.getText(sourceFile)}=${text}`);
    }
    if (ts.isPropertyAssignment(node) && VISIBLE_PROPS.has(node.name.getText(sourceFile).replace(/['"]/g, ''))
        && sourceFile.fileName.endsWith('.tsx')) {
      const text = literalText(node.initializer);
      if (text !== null && hasLetters(text)) report(node, 'visible_option', `${node.name.getText(sourceFile)}: ${text}`);
    }
    if (ts.isCallExpression(node) && ALERT_CALLS.has(node.expression.getText(sourceFile))) {
      for (const arg of node.arguments) {
        const text = literalText(arg);
        if (text !== null && hasLetters(text)) report(arg, 'alert_literal', text);
      }
    }
    if ((ts.isStringLiteral(node) || ts.isNoSubstitutionTemplateLiteral(node)) && !isImportOrTypeContext(node)) {
      for (const term of FORBIDDEN_TERMS) {
        if (term.test(node.text)) report(node, 'renamable_term', node.text);
      }
    }
    if (ts.isJsxText(node)) {
      for (const term of FORBIDDEN_TERMS) if (term.test(node.text)) report(node, 'renamable_term', node.text);
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  // One finding per node and rule is enough.
  const seen = new Set();
  return findings.filter((f) => !seen.has(`${f.line}:${f.rule}:${f.text}`) && seen.add(`${f.line}:${f.rule}:${f.text}`));
}

export function listSourceFiles(dir) {
  const out = [];
  for (const entry of readdirSync(dir)) {
    const path = join(dir, entry);
    if (statSync(path).isDirectory()) {
      if (entry !== 'locales' && entry !== 'node_modules') out.push(...listSourceFiles(path));
    } else if (/\.(ts|tsx)$/.test(entry) && !entry.endsWith('.d.ts')) {
      out.push(path);
    }
  }
  return out;
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  const files = listSourceFiles('src');
  const findings = files.flatMap((file) => checkSource(file, readFileSync(file, 'utf8')));
  if (findings.length) {
    for (const f of findings) console.error(`${f.file}:${f.line} [${f.rule}] ${f.text}`);
    console.error(`UI string lint failed: ${findings.length} finding(s). Words: t('…') from '@/i18n'; numbers/dates: useFormat(); now: serverNow().`);
    process.exit(1);
  }
  console.log(`UI string lint passed (${files.length} files).`);
}

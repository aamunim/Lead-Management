import { useColorScheme } from 'react-native';

// Minimal light/dark colours until the design system (0A.13) replaces them with tokens.
const light = { text: '#1b1b1f', muted: '#5d5e67', border: '#9a9aa3', surface: '#ffffff', accent: '#1b6ef3', accentText: '#ffffff', danger: '#b00020', background: '#f2f2f2' };
const dark = { text: '#ececf1', muted: '#a9aab3', border: '#5d5e67', surface: '#1f1f24', accent: '#8ab4ff', accentText: '#0b1020', danger: '#ff8a80', background: '#121214' };
export type Colors = typeof light;

export function useColors(): Colors {
  return useColorScheme() === 'dark' ? dark : light;
}

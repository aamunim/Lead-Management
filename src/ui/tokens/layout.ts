// Spacing, radius, touch and elevation tokens (0A.13). 4-point grid.
export const space = { xxs: 2, xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32, xxxl: 48 } as const;
export const radius = { sm: 8, md: 12, lg: 16, xl: 28, full: 999 } as const;
/** Minimum touch target (Ch 47.8): every pressable element is at least 48 × 48 dp. */
export const TOUCH = 48;
export const MAX_CONTENT_WIDTH = 720; // web / tablets: readable line length

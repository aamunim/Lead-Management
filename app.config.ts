/// <reference types="node" />
import { existsSync } from 'node:fs';
import type { ConfigContext, ExpoConfig } from 'expo/config';

// Dynamic layer on top of app.json (milestone 0A.02).
//
// 1. Firebase config (google-services.json) is never committed (lesson 12). CI writes it from a base64
//    secret and points GOOGLE_SERVICES_FILE at it; locally the file is optional.
// 2. Branded apps (D12, Phase 5) reuse the same code: CI may override the name, package and scheme with
//    BRAND_APP_NAME / BRAND_ANDROID_PACKAGE / BRAND_SCHEME. Without them the shared app's identity from
//    app.json is used.
export default ({ config }: ConfigContext): ExpoConfig => {
  const googleServicesFile =
    process.env.GOOGLE_SERVICES_FILE ?? (existsSync('./google-services.json') ? './google-services.json' : undefined);

  const name = process.env.BRAND_APP_NAME ?? config.name ?? '';
  const slug = config.slug ?? '';
  const androidPackage = process.env.BRAND_ANDROID_PACKAGE ?? config.android?.package;
  const scheme = process.env.BRAND_SCHEME ?? config.scheme;

  return {
    ...config,
    name,
    slug,
    scheme,
    android: {
      ...config.android,
      package: androidPackage,
      ...(googleServicesFile ? { googleServicesFile } : {}),
    },
    extra: {
      ...config.extra,
      appEnv: process.env.APP_ENV ?? 'development',
    },
  };
};

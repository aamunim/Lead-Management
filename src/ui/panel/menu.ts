import type { Href } from 'expo-router';

import type { IconName } from '@/ui/components';

// Panel menu (0B.02-T6, Ch 5.3; Proposed structure — the owner approves at the checkpoint). Each item needs a
// platform right; items built later show "coming in <milestone>".
export type PanelMenuItem = { key: string; href: Href; icon: IconName; permission: string; builtIn: string | null };

export const PANEL_MENU: PanelMenuItem[] = [
  { key: 'dashboard', href: '/panel', icon: 'dashboard', permission: 'platform.view', builtIn: null },
  { key: 'institutions', href: '/panel/institutions', icon: 'apartment', permission: 'platform.view', builtIn: null },
  { key: 'groups', href: '/panel/groups', icon: 'account-tree', permission: 'platform.view', builtIn: '1.19' },
  { key: 'profiles', href: '/panel/profiles', icon: 'category', permission: 'platform.profiles', builtIn: null },
  { key: 'providers', href: '/panel/providers', icon: 'hub', permission: 'platform.integrations', builtIn: '0B.11' },
  { key: 'announcements', href: '/panel/announcements', icon: 'campaign', permission: 'platform.view', builtIn: '1.33' },
  { key: 'requests', href: '/panel/requests', icon: 'inbox', permission: 'platform.view', builtIn: '0B.07' },
  { key: 'inbox', href: '/panel/inbox', icon: 'bug-report', permission: 'platform.developer', builtIn: '1.18' },
  { key: 'users', href: '/panel/users', icon: 'admin-panel-settings', permission: 'platform.users', builtIn: null },
];

export const INSTITUTION_TABS = ['overview', 'messaging', 'notifications', 'payments', 'integrations', 'domain', 'plan', 'labels', 'audit'] as const;

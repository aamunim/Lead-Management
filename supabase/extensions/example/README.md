# Example extension (`example`, schema `ext_example`)

A tiny extension that exists only to prove the extension rules (0A.09). It is never shown to users.

- **Tables:** `ext_example.notes`, `ext_example.setting_change_counts` (both with `institution_id`, RLS, and visible
  only while the extension is on for the active institution).
- **RPCs:** `public.ext_example_note_add(p_body)`, `public.ext_example_notes_list()`. Calling one while the
  extension is off fails with `extension_disabled`.
- **Emits:** `example.note_added` v1.
- **Listens to:** `setting.changed` → `ext_example.on_setting_changed` (counts setting changes per institution).
- **Permissions / labels:** none yet (the registries arrive in 0A.17 / 0A.10).
- **Remove:** `uninstall.sql`. The core keeps working without it.

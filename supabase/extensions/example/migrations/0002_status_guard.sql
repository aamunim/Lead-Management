-- 0B.07: extension tables carry the lifecycle guard too (read-only / suspended / closed institutions refuse writes).
select app.attach_status_guard('ext_example.notes');
select app.attach_status_guard('ext_example.setting_change_counts');

-- The pet companion feature was removed from the app (PR #116) and the
-- backend no longer reads or writes these columns. The feature never shipped
-- outside internal builds, so any stored values are test data.
alter table profiles drop constraint if exists profiles_pet_preset_check;
alter table profiles drop column if exists pet_preset;
alter table profiles drop column if exists pet_name;
alter table profiles drop column if exists pet_selected_at;

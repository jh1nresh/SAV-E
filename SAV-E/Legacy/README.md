# Legacy main-app designs

The shipping main app uses `Views/InkNotebook`: its paper, Iansui type, rough ink outlines and arrival-only accent are the current visual system. Its welcome and Passport language controls use `SaveInkLanguageSheet`.

This directory archives the previous five-tab shell, Atlas/Doodle screens, old Passport, map chrome, planning, trips and related view components. Prototype-only source is also isolated under `Prototypes/AtlasPostcard/Legacy/Sources`.

Sources stay compiled for existing models, compatibility routes and regression coverage. Archival does not remove saved places, account behavior, imports, sharing, attribution, or tests. Current Ink screens must not instantiate these archived designs; build success alone does not prove that boundary.

Active auth/loading and first-run onboarding remain outside this directory because the separate signin redesign owns them. Shared services, localization, models, view models, reusable image/attribution utilities and theme definitions stay in their established locations. App Clip has a separate design contract and is unchanged.

Reference images, fonts, approved map evidence and frozen test baselines remain at their original paths. They are verification evidence, not a component catalog for new main-app UI. Do not copy legacy screen styles back into Ink when adding a control.

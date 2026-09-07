# Documentation

[Repository home](../README.md) · [Specification index](../specs/README.md)

## Guides

| Document | Purpose |
|---|---|
| [Product overview](product-overview.md) | App surfaces, stack, and product boundaries |
| [Local setup](setup.md) | Local configuration and Xcode project generation |
| [Verification](verification.md) | Native, backend, web, and fixture checks |
| [Sharing](sharing.md) | Share routes, Universal Links, and App Clip configuration |
| [Release and TestFlight](releasing.md) | Signing, archives, upload, and release prerequisites |

## Contracts and runbooks

| Document | Purpose |
|---|---|
| [Agent contribution contract](../AGENTS.md) | Scope, verification, PR, and release rules |
| [Design contract](../DESIGN.md) | Design intent and product-state semantics |
| [Runtime agent contract](save-agent-contract.md) | Evidence and memory boundaries |
| [Public test readiness](save-public-test-readiness.md) | Readiness checklist and evidence requirements |
| [Backend rebuild runbook](2026-08-04-backend-rebuild-runbook.md) | Dated backend recovery procedure |
| [App Store Connect rename](app-store-connect-savvy-rename.md) | Savvy naming procedure |

## Security reviews

- [2026-07-09 repository audit](security/2026-07-09-save-full-repo-security-audit.md)
- [2026-06-12 differential review](security/2026-06-12-pr402-differential-review.md)

## Historical records

These describe past plans or observed states. They are not current release evidence.

- [Original iOS scaffold brief](archive/original-ios-scaffold.md) — moved from root `SPEC.md`.
- [Build 106 release snapshot](archive/build-106-release-state.md) — last verified 2026-08-25.

## Where new files belong

Use `docs/` for reusable operating guides, `docs/security/` for security review records, and `docs/archive/` for explicitly historical documentation. Product proposals and their receipts belong in [specs/](../specs/README.md). Brand artwork and studies belong in [design-assets/](../design-assets/); CI visual references remain in [AtlasPostcard](../Prototypes/AtlasPostcard/README.md).

Keep the root focused on the README, contribution/design contracts, source directories, and tool-required project/configuration files. Add new documents to the relevant index. Preserve linked spec paths and executable asset paths unless their consumers are updated together.

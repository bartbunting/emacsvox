# Emacsvox repository workflow

- Before changing architecture, workflows, versioning, release tooling, or
  documentation publication, read every architecture decision record under
  `docs/adr/` and follow all accepted decisions. Do not rely on a single ADR in
  isolation; later records may refine earlier decisions.
- Preserve named authors and copyright holders when editing source headers;
  follow the attribution and licensing policy in `docs/adr/`. Run
  `make headers-check` after changing a maintained Lisp header, attribution,
  licence notice, or package metadata. Do not apply the default project licence
  to a file listed as an exception in `THIRD_PARTY_NOTICES`.
- Preserve existing tracked and untracked work. Never clean, reset, stash, or
  discard a dirty worktree merely to satisfy a build precondition.
- Use the Emacs selected by the ignored `local.mk` and run `make check-emacs`
  before diagnosing compiler failures. Emacsvox requires Emacs 31 or newer;
  never compile it with an older system `emacs`.
- After an ordinary Lisp edit, run `make bytecode` before restarting the live
  Emacsvox profile. Run `make bytecode-check` as a non-mutating preflight; it
  also rejects byte-code produced by a different Emacs version.
- After switching branches, pulling, or changing Lisp macros/public interfaces,
  run `make bytecode-rebuild`; ignored in-tree `.elc` files can otherwise
  survive from the previous source tree. This target removes generated `.elc`
  files and regenerates them; it does not clean source changes.
- Tests deliberately prefer source and therefore do not prove that live
  byte-code is current. Verify in a fresh Emacs after compiling; do not rely on
  reloading one file when compiled dependents may already be resident.
- Local `.elc` files are build and preflight inputs only. They are ignored and
  never distributed; releases contain the `.el` sources.
- `VERSION` is the canonical release identifier; accepted calendar-versioning
  policy is recorded under `docs/adr/`. Run `make version-check` after changing
  it, package metadata, or the current NEWS heading. In a separate clean
  release worktree, run `make bytecode-rebuild`; `make release-artifact` then
  runs the guarded release gate and records the checked source commit. Inspect
  it before `make release-tag` and `make release-publish`. Never tag or push
  around a failed gate. Treat release preparation and release publication as
  separate approvals: never create or push a release tag, or run
  `make release-publish`, without fresh explicit user permission naming the
  release. A general instruction to continue, commit, push a branch, or publish
  documentation is not permission to publish a tagged release.
- Reports and internal notes do not require an Emacsvox build. The maintained
  manual source is `docs/manual/emacsvox.org`, its included user chapters under
  `docs/manual/chapters/`, and its final developer guide under
  `docs/developer/`. Follow the audience boundary in the accepted documentation
  ADRs. Iterate with `make docs-org-preview`; it lints and exports Org to
  Texinfo, Info, and HTML below ignored
  `.docs-preview/org-manual/` without loading Emacsvox. Run `make docs-update`
  once the text settles to update the tracked generated Texinfo body and Info
  artifacts; never edit those generated files directly. For retained Texinfo
  manuals, use `make docs-preview DOCS_MANUAL=...`.
- When public Lisp documentation changes, first bring byte-code current under
  the rules above, then run `make docs-reference`; `make docs-generate` remains
  the comprehensive update.
- Before review, merge, or deployment, run the non-mutating
  `make docs-release-check` (`make docs-check` is a compatibility alias). Use
  `make docs-publish` only for an explicit preview directory. Publish the public
  manual from a clean, committed source worktree with `make docs-publish-pages
  DOCS_PUBLISH_DIR=/path/to/gh-pages-worktree`; it validates and publishes one
  staged render and records source and toolchain provenance. Documentation
  targets never commit or push: inspect and commit the `gh-pages` worktree
  separately. Run `make docs-check-external` only when network link checking is
  intended.
- `make windows-omnivox` is the reproducible clean-release path. For local
  testing from dirty Emacsvox or Omnivox worktrees, use
  `make windows-omnivox-dev`; it records both tracked-diff hashes in provenance.
- The ordinary WSL2 binary-install route is `bin/emacsvox-wsl-install`; its
  pinned inputs and hashes live in `etc/wsl-install.conf`. Treat both as release
  tooling, keep the installer per-user, and run its isolated x64/ARM64 tests
  plus one real newly pinned archive check before changing the public guide.
- Do not bypass the Omnivox release target manually or clean either repository
  to make the release guard pass.

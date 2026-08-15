# Emacsvox repository workflow

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
- `make windows-omnivox` is the reproducible clean-release path. For local
  testing from dirty Emacsvox or Omnivox worktrees, use
  `make windows-omnivox-dev`; it records both tracked-diff hashes in provenance.
- Do not bypass the Omnivox release target manually or clean either repository
  to make the release guard pass.

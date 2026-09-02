# Emacsvox contributor guide

Repository workflow and safety requirements live in `AGENTS.md` and are
authoritative. This file is a compact architecture and documentation index for
automated coding tools; it does not replace those instructions.

## Project boundary

Emacsvox is an Emacs 31+ audio desktop derived from Emacspeak. Active project
APIs and configuration use the `emacsvox-*` and engine-independent `tts-*`
namespaces. `dtk-*` is reserved for actual DECtalk backends. References to
Emacspeak remain only for attribution, historical records, external
identifiers, and the pinned behavioral comparison checkout.

The canonical current documents are:

- `README.org` — user overview, Omnivox integration, and quick installation.
- `docs/developer/integration-maintenance.org` — source-checkout, byte-code,
  integration, and release lifecycle.
- `etc/NEWS` — current user-visible changes.
- `etc/aural-presentation-reference.org` — generated Aural user and author
  contract.
- `servers/omnivox-release/README.org` — reproducible Windows bundle contract.
- `test/README.org` — local and pinned-reference test workflows.

`archive/emacsvox/migrations/` retains point-in-time migration and design
history. `archive/emacspeak/` preserves
inherited release notes, experiments, and machine-specific audio material.
Do not infer current behavior from an archive when a canonical document or
current code says otherwise.

## Build and checks

Use the Emacs executable selected by the ignored `local.mk`. Never diagnose or
compile this repository with an older system Emacs.

```sh
make check-emacs
make all                 # configure and build a complete checkout
make bytecode            # incremental build after an ordinary Lisp edit
make bytecode-check      # non-mutating startup/deployment preflight
make bytecode-rebuild    # branch, pull, macro, or public-interface change

make test
make aural-audit
make advice-audit
make name-audit
make tts-audit
```

Tests prefer source and therefore do not prove that ignored in-tree byte-code
is current. Use `make reference-test EMACSPEAK_DIR=/path/to/pinned/checkout`
only for the fixed comparison described in `test/README.org`.

The Aural reference is generated. Edit its maintained prose or tables in
`utils/emacsvox-aural-audit.el`, run `make aural-reference`, and commit the
generator and generated file together.

Build individual speech servers with `make espeak`, `make swiftmac`,
`make outloud`, or `make dtk`. For Omnivox, the reproducible release path is
`make windows-omnivox`; use `make windows-omnivox-dev` for local testing from
active tracked changes. Restart Emacsvox after staging a new Omnivox runtime,
because an existing process keeps running its original content-addressed
executable.

## Runtime architecture

The ordinary speech path begins in high-level commands and package advice in
`lisp/emacsvox-speak.el` and the `lisp/emacsvox-*.el` integrations.
`lisp/tts-speak.el` owns generic speech-server processes, state, text
preparation, protocol writes, tracked callbacks, and process retirement.
`lisp/voice-setup.el` and `lisp/voice-defs.el` map faces and personalities to
engine-independent voice properties.

The semantic Aural path is:

```text
integration/submission
  -> source snapshot and providers
  -> rule matching and planning
  -> concrete-plan compilation
  -> delivery-policy transport
  -> tts-speak and the selected server adapter
```

The corresponding implementation is split across
`emacsvox-aural-submission.el`, `emacsvox-aural-source.el`, provider modules,
`emacsvox-aural-rules.el`, `emacsvox-aural-planner.el`,
`emacsvox-aural-compiler.el`, `emacsvox-aural-concrete.el`, and
`emacsvox-aural-transport.el`.

For Omnivox, `lisp/omnivox-voices.el` negotiates capabilities, inventory,
logical voices, runtime routing, marker events, and structured presentation
timeline v3. Structured keyed replacement is sent immediately so Omnivox can
cancel only the matching domain. The short Emacs idle delay is a legacy
fallback; ordered and urgent submissions are not delayed. The server remains
responsible for synthesis, generation-safe domain cancellation, audio
buffering, and truthful terminal events.

## Aural invariants

- Integrations publish semantic facts and occasions; presentation rules choose
  speech, voice, cue, tone, pause, effects, and spatial style.
- Capture facts, faces, properties, narrowing, and source context in the source
  buffer before copying text into a scratch or notification buffer.
- Submit one complete presentation transaction. Do not nest `tts-speak`,
  `emacsvox-icon`, or another complete Aural resolver inside a native
  submission.
- Keep compatibility cues as data in the same transaction so delivery order,
  cancellation, history, and callbacks share one lifecycle.
- `ordered` preserves accepted work, `replaceable` supersedes only its owner
  and replacement domain, and `urgent` performs explicit stream interruption.
- Generated history is committed only after successful delivery and must not
  retain live source buffers.
- The fixed compatibility baseline, automatic module fragments, ordered
  Presentation Options, and scoped overrides are separate layers. Selectable
  presentation schemes are retired.

## Package support and naming

Use named native `advice-add` functions and test the interactive target and
return-value behavior. Do not introduce `defadvice`, positional advice
accessors, anonymous advice functions, or compatibility aliases for removed
Emacspeak and generic DTK names.

New package support normally belongs in `lisp/emacsvox-PACKAGE.el`, is lazily
registered from `lisp/emacsvox.el`, publishes semantic facts at its feedback
boundary, and receives focused ERT coverage under `test/`.

Use `EMACSVOX_DIR` for the checkout root, `EMACSVOX_PLAY` for the server audio
player, and `TTS_PROGRAM` for speech-server selection. The removed
`EMACSPEAK_*`, generic `DTK_*`, `emacspeak-*`, and generic `dtk-*` interfaces
have no compatibility layer.

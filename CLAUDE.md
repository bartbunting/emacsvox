# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Emacsvox is a fork of Emacspeak - a complete audio desktop that extends Emacs to be fully functional via speech output. The project has been maintained since 1995 by T. V. Raman and provides speech interfaces for 200+ Emacs packages.

**✨ MODERNIZATION STATUS: COMPLETE (December 2024)**
- All 1,961 defadvice forms converted to modern advice-add
- Minimum Emacs version: 31+
- 100% lexical-binding throughout
- Modern elisp patterns and formatting
- Fully compliant with Emacs 31+ standards

## Build and Development Commands

### Initial Setup
```bash
make config          # Configure build environment
make                 # Build core Emacspeak (compiles ~245 elisp files)
```

### Building TTS Servers
```bash
make espeak          # Build native eSpeak server (most common)
make swiftmac        # Build macOS Swift-based TTS server
make outloud         # Build ViaVoice Outloud server (Linux)
make dtk             # Build software DECTalk server
```

### Complete Rebuild
```bash
make q               # Clean, config, build everything including muggles
```

### Testing
```bash
# Launch Emacspeak in vanilla Emacs to test
emacs -q -l lisp/emacspeak-setup.el

# Or use the user's preferred method
em                   # Launch emacs
emc <file>          # Open file in emacsclient
```

### Compilation
```bash
cd lisp && make      # Compile all elisp files to .elc
cd lisp && make clean # Remove compiled files
```

## Architecture Overview

### Core Speech Pipeline

1. **High-Level API** (`emacspeak-speak.el`)
   - Functions like `emacspeak-speak-line`, `emacspeak-speak-region`, `emacspeak-speak-buffer`
   - Used by all speech-enabling modules

2. **TTS Interface Layer** (`dtk-speak.el`)
   - Manages external TTS server process via stdin/stdout
   - Preprocesses text (handles pronunciations, invisible text, caps)
   - Chunks text and applies voice personalities based on text properties
   - Core function: `dtk-speak` - sends text to TTS server
   - Process commands: `dtk-interp-queue`, `dtk-interp-speak`, `dtk-interp-silence`

3. **Voice System** (`voice-setup.el`, `voice-defs.el`)
   - "Voices" = audio properties (pitch, rate, stress) - analogous to fonts
   - "Personalities" = text properties carrying voice info - analogous to faces
   - Maps Emacs faces to voice personalities for audio formatting

4. **TTS Servers** (`servers/`)
   - External Tcl scripts that interface with actual speech engines
   - Simple text protocol: `q {text}` (queue), `d` (deliver/speak), `s` (stop)
   - Share common functionality via `tts-lib.tcl`

### Advice-Based Speech Integration

The codebase uses Emacs' modern `advice-add` system extensively (fully migrated from deprecated `defadvice` in December 2024):

- **Core advice** (`emacspeak-advice.el`): Uses advice-add to wrap fundamental Emacs functions
- **Package-specific modules** (`emacspeak-PACKAGE.el`): 193 modules with ~1,964 advice functions
- **Lazy loading**: Speech modules only load when their base package is used via `with-eval-after-load`
- **Naming convention**: All advice functions prefixed with `ems--FUNCTION-CLASS` (e.g., `ems--next-line-after`)

### Directory Structure

- `lisp/` - 245 elisp modules (core + package speech enablers)
- `servers/` - TTS server implementations (espeak, mac, outloud, cloud variants)
- `sounds/` - Auditory icon themes (chimes/, 3d/, prompts/)
- `etc/` - Configuration files, tables, utilities
- `info/` - Documentation and manuals
- `tvr/` - Personal configuration (T. V. Raman's setup)

## Key Files

- `lisp/emacspeak.el` - Main entry point, package extension registry
- `lisp/emacspeak-setup.el` - Initialization entry point
- `lisp/dtk-speak.el` - TTS interface layer (~1800 lines)
- `lisp/emacspeak-speak.el` - High-level speech API (~2300 lines)
- `lisp/emacspeak-advice.el` - Core Emacs function wrapping
- `lisp/emacspeak-preamble.el` - Paths and initialization
- `servers/tts-lib.tcl` - Common TTS server library

## Development Patterns

### Adding Speech Support for a Package

1. Create `lisp/emacspeak-PACKAGE.el`
2. Use `defadvice` to wrap key functions with speech feedback
3. Call high-level speech functions from `emacspeak-speak.el`
4. Register in `emacspeak.el` using `with-eval-after-load`

### Speech Feedback Pattern
```elisp
(defadvice some-function (after emacspeak pre act comp)
  "Provide speech feedback."
  (when (ems-interactive-p)
    (emacspeak-icon 'task-done)
    (emacspeak-speak-line)))
```

### Voice Application Pattern
```elisp
;; Apply voice personality based on semantic meaning
(put-text-property start end 'personality voice-annotate)
```

## TTS Server Protocol

Simple text-based commands sent to server stdin:
- `q {text}` - Queue text for speaking
- `c {code}` - Queue voice control code
- `sh 100` - Queue 100ms silence
- `t 440 100` - Queue 440Hz tone for 100ms
- `d` - Deliver (speak all queued text)
- `s` - Stop speaking
- `tts_set_speech_rate N` - Set speech rate
- `tts_set_punctuations mode` - Set punctuation verbosity

## Installation

After building, add to `.emacs`:
```elisp
(load-file "/path/to/emacsvox/lisp/emacspeak-setup.el")
```

Requires:
- Emacs 29.1 or later
- SoX for playing audio files
- curl for internet features
- TTS engine (espeak, mac speech, etc.)

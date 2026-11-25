// Copyright (C) 2026 Emacsvox contributors
// SPDX-License-Identifier: GPL-2.0-or-later

// The native promise settles after playback or cancellation. Keep its identity
// through Stop so delayed results cannot replace the current timing readout.
function mixerAdapters(native, directSpeech, timing, chimeReady = () => false) {
  let generation = 0;
  return {
    speech: {
      getAvailableVoicesAsync: () => directSpeech.getAvailableVoicesAsync(),
      stop(all = true) {
        generation++;
        return native.stop(all);
      },
      speak(text, options) {
        const owner = ++generation;
        native.speak(text, options.voice ?? null, options.rate, options.mixSample === true).then(result => {
          if (owner !== generation) return;
          const elapsed = result.firstBufferMs;
          timing(elapsed >= 0 ? 'First speech buffer after ' + elapsed + ' milliseconds.' : 'No speech buffer received.');
          if (result.state === 'done') options.onDone();
          else {
            options.onError();
            timing('Mixer reported ' + result.state + '.');
          }
        }).catch(() => { if (owner === generation) options.onError(); });
      },
    },
    cuePlayer: {
      isLoaded: true, currentTime: 0,
      play: () => native.cue(),
      pause: () => native.stopCue ? native.stopCue() : native.stopEffects(),
    },
    visualLinePlayer: native.chime && {
      get isLoaded() { return chimeReady(); }, currentTime: 0,
      play: () => native.chime(),
      pause: () => native.stopCue(),
    },
  };
}
module.exports = { mixerAdapters };

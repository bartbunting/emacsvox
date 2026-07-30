# Windows Speech Server Provenance

The standalone `windows-outloud` server is derived from Emacspeak's
`servers/outloud`, copyright T. V. Raman. The standalone `windows-dtk` server
is derived from Emacspeak's `servers/dtk-soft`, copyright T. V. Raman. Their
native Windows adaptations are copyright 2026 Bart Bunting.

The native Windows bridge, transport, and audio-player sources were written by
Bart Bunting in 2026. The standalone variants were prepared from Emacspeak
baseline `7482f8e27`; their standalone and external layout work is recorded in
commits `582994db3`, `134fd499e`, and `b3698c254`. Emacsvox imported the owned
server stack from `emacspeak-support` commit `e3c76cf`.

These sources are licensed under the GNU General Public License, version 2 or,
at your option, any later version. See this distribution's `COPYING` file.

No proprietary Eloquence files are included. The DECtalk runtime is also not
stored in the repository; its build process downloads a separately maintained
runtime, verifies its pinned checksum, and extracts it locally. Review the
applicable third-party runtime terms before redistribution.

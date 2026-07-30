// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

internal static class EloquenceBridgeLauncher
{
    internal static int Main(string[] args)
    {
        return WindowsSpeechBridgeLauncher.Run("EloquenceBridge32.exe",
            "The 32-bit Eloquence bridge", args);
    }
}

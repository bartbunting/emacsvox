// Copyright (C) 2026 Emacsvox Contributors
// SPDX-License-Identifier: GPL-2.0-or-later
// Test wrapper around the production persistent bridge launcher.

internal static class TimeoutLauncher
{
    internal static int Main(string[] args)
    {
        return WindowsSpeechBridgeLauncher.Run(
            "HangingBridge.exe", "The hanging test bridge", args);
    }
}

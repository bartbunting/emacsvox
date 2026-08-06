// Copyright (C) 2026 Emacsvox Contributors
// SPDX-License-Identifier: GPL-2.0-or-later
// Deterministic child bridge used to verify launcher request timeouts.

using System;
using System.Threading;

internal static class HangingBridge
{
    internal static int Main()
    {
        if (Console.ReadLine() != null)
        {
            Thread.Sleep(Timeout.Infinite);
        }
        return 0;
    }
}

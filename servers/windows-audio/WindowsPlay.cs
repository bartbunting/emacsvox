// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

internal static class WindowsPlay
{
    private static readonly object cacheLock = new object();
    private static readonly Dictionary<string, byte[]> soundCache =
        new Dictionary<string, byte[]>(StringComparer.OrdinalIgnoreCase);
    private static readonly WaveOutQueue playbackQueue = new WaveOutQueue();

    private static byte[] LoadSound(string path)
    {
        lock (cacheLock)
        {
            byte[] cached;
            if (soundCache.TryGetValue(path, out cached))
            {
                return cached;
            }
        }

        byte[] sound = File.ReadAllBytes(path);
        lock (cacheLock)
        {
            soundCache[path] = sound;
        }
        return sound;
    }

    private static string Execute(string request, out bool quit)
    {
        quit = false;
        if (request == "PING")
        {
            return "OK";
        }
        if (request == "QUIT")
        {
            quit = true;
            return "OK";
        }
        if (request == "CANCEL")
        {
            playbackQueue.Cancel();
            return "OK";
        }

        const string prefix = "PLAY ";
        if (!request.StartsWith(prefix, StringComparison.Ordinal))
        {
            return "ERR invalid request";
        }

        string path = Encoding.UTF8.GetString(Convert.FromBase64String(
            request.Substring(prefix.Length)));
        if (!File.Exists(path))
        {
            return "ERR file not found";
        }
        playbackQueue.Enqueue(LoadSound(path));
        return "OK";
    }

    internal static int Main(string[] args)
    {
        if (args.Length != 1 || args[0] != "--stdio")
        {
            Console.Error.WriteLine("Usage: WindowsPlay.exe --stdio");
            return 2;
        }

        try
        {
            string request;
            try
            {
                while ((request = Console.ReadLine()) != null)
                {
                    bool quit;
                    Console.WriteLine(Execute(request, out quit));
                    Console.Out.Flush();
                    if (quit)
                    {
                        break;
                    }
                }
            }
            finally
            {
                playbackQueue.Dispose();
            }
            return 0;
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(error.Message);
            return 1;
        }
    }
}

// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Text;

internal static class WindowsSpeechBridgeProtocol
{
    internal delegate string RequestHandler(string command, string argument,
        out bool quit);

    internal static string DecodeText(string payload)
    {
        return Encoding.UTF8.GetString(Convert.FromBase64String(payload));
    }

    internal static int ParseInteger(string value, string name)
    {
        int result;
        if (!Int32.TryParse(value, out result))
        {
            throw new ArgumentException("Invalid " + name + ": " + value);
        }
        return result;
    }

    internal static void WriteError(Exception error)
    {
        string message = error.GetType().Name + ": " + error.Message;
        Console.WriteLine("ERR " + Convert.ToBase64String(
            Encoding.UTF8.GetBytes(message)));
        Console.Out.Flush();
    }

    internal static int Run(RequestHandler handler)
    {
        string line;
        while ((line = Console.ReadLine()) != null)
        {
            int separator = line.IndexOf(' ');
            string command = separator < 0 ? line :
                line.Substring(0, separator);
            string argument = separator < 0 ? "" :
                line.Substring(separator + 1);
            command = command.ToUpperInvariant();

            bool quit = false;
            try
            {
                Console.WriteLine(handler(command, argument, out quit));
            }
            catch (Exception error)
            {
                WriteError(error);
                if (quit)
                {
                    break;
                }
                continue;
            }
            Console.Out.Flush();
            if (quit)
            {
                break;
            }
        }
        return 0;
    }
}

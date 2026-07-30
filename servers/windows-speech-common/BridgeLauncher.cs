// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading;

internal static class WindowsSpeechBridgeLauncher
{
    private static string QuoteArgument(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static void CopyErrors(StreamReader errors)
    {
        string line;
        while ((line = errors.ReadLine()) != null)
        {
            Console.Error.WriteLine(line);
        }
    }

    internal static int Run(string childName, string description,
        string[] args)
    {
        string directory = AppDomain.CurrentDomain.BaseDirectory;
        string bridge = Path.Combine(directory, childName);
        if (!File.Exists(bridge))
        {
            Console.Error.WriteLine("Bridge executable not found: " + bridge);
            return 1;
        }

        ProcessStartInfo startInfo = new ProcessStartInfo();
        startInfo.FileName = bridge;
        startInfo.UseShellExecute = false;
        startInfo.CreateNoWindow = true;
        startInfo.RedirectStandardInput = true;
        startInfo.RedirectStandardOutput = true;
        startInfo.RedirectStandardError = true;
        if (args.Length > 0)
        {
            StringBuilder arguments = new StringBuilder();
            for (int index = 0; index < args.Length; ++index)
            {
                if (index > 0)
                {
                    arguments.Append(' ');
                }
                arguments.Append(QuoteArgument(args[index]));
            }
            startInfo.Arguments = arguments.ToString();
        }

        using (Process process = Process.Start(startInfo))
        {
            Thread errorThread = new Thread(
                delegate() { CopyErrors(process.StandardError); });
            errorThread.IsBackground = true;
            errorThread.Start();

            string request;
            while ((request = Console.ReadLine()) != null)
            {
                process.StandardInput.WriteLine(request);
                process.StandardInput.Flush();
                string response = process.StandardOutput.ReadLine();
                if (response == null)
                {
                    Console.Error.WriteLine(description +
                        " exited unexpectedly");
                    break;
                }
                Console.WriteLine(response);
                Console.Out.Flush();
                if (request.Equals("QUIT",
                    StringComparison.OrdinalIgnoreCase))
                {
                    break;
                }
            }

            process.StandardInput.Close();
            process.WaitForExit();
            errorThread.Join(1000);
            return process.ExitCode;
        }
    }
}

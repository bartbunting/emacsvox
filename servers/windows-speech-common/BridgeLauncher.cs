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
    private const int DefaultRequestTimeoutMilliseconds = 10000;
    private const int DefaultSyncTimeoutMilliseconds = 600000;
    private const string RequestTimeoutEnvironmentVariable =
        "EMACSVOX_WINDOWS_SPEECH_RPC_TIMEOUT_MS";
    private const string SyncTimeoutEnvironmentVariable =
        "EMACSVOX_WINDOWS_SPEECH_SYNC_TIMEOUT_MS";

    private sealed class RoundTripWorker
    {
        private readonly StreamWriter input;
        private readonly StreamReader output;
        private readonly AutoResetEvent requestReady = new AutoResetEvent(false);
        private readonly ManualResetEvent responseReady =
            new ManualResetEvent(false);
        private readonly Thread thread;
        private string request;
        private string response;
        private Exception failure;
        private bool stopping;

        internal RoundTripWorker(StreamWriter input, StreamReader output)
        {
            this.input = input;
            this.output = output;
            thread = new Thread(Run);
            thread.IsBackground = true;
            thread.Start();
        }

        private void Run()
        {
            while (true)
            {
                requestReady.WaitOne();
                if (stopping)
                {
                    return;
                }
                try
                {
                    input.WriteLine(request);
                    input.Flush();
                    response = output.ReadLine();
                }
                catch (Exception error)
                {
                    failure = error;
                }
                responseReady.Set();
            }
        }

        internal string Execute(string value, int timeoutMilliseconds)
        {
            request = value;
            response = null;
            failure = null;
            responseReady.Reset();
            requestReady.Set();
            if (!responseReady.WaitOne(timeoutMilliseconds))
            {
                throw new TimeoutException("request timed out after " +
                    timeoutMilliseconds + " milliseconds");
            }
            if (failure != null)
            {
                throw new IOException("bridge request failed", failure);
            }
            return response;
        }

        internal void Stop()
        {
            stopping = true;
            requestReady.Set();
            thread.Join(1000);
        }
    }

    private static string QuoteArgument(string value)
    {
        return "\"" + value.Replace("\"", "\\\"") + "\"";
    }

    private static int TimeoutFromEnvironment(string name, int fallback)
    {
        string value = Environment.GetEnvironmentVariable(name);
        if (String.IsNullOrEmpty(value))
        {
            return fallback;
        }
        int timeout;
        if (!Int32.TryParse(value, out timeout) || timeout <= 0)
        {
            throw new ArgumentException(name +
                " must be a positive number of milliseconds: " + value);
        }
        return timeout;
    }

    private static string RequestCommand(string request)
    {
        int separator = request.IndexOf(' ');
        return separator < 0 ? request : request.Substring(0, separator);
    }

    private static int RequestTimeout(string request, int ordinary, int sync)
    {
        string command = RequestCommand(request);
        return command.Equals("SYNC", StringComparison.OrdinalIgnoreCase) ?
            sync : ordinary;
    }

    private static void WriteFatal(Exception error)
    {
        string message = error.GetType().Name + ": " + error.Message;
        Console.WriteLine("FATAL " + Convert.ToBase64String(
            Encoding.UTF8.GetBytes(message)));
        Console.Out.Flush();
    }

    private static void Kill(Process process)
    {
        try
        {
            if (!process.HasExited)
            {
                process.Kill();
            }
        }
        catch (InvalidOperationException)
        {
            // The process exited between the check and the kill request.
        }
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

        int requestTimeout;
        int syncTimeout;
        try
        {
            requestTimeout = TimeoutFromEnvironment(
                RequestTimeoutEnvironmentVariable,
                DefaultRequestTimeoutMilliseconds);
            syncTimeout = TimeoutFromEnvironment(
                SyncTimeoutEnvironmentVariable,
                DefaultSyncTimeoutMilliseconds);
        }
        catch (Exception error)
        {
            WriteFatal(error);
            return 1;
        }

        using (Process process = Process.Start(startInfo))
        {
            Thread errorThread = new Thread(
                delegate() { CopyErrors(process.StandardError); });
            errorThread.IsBackground = true;
            errorThread.Start();

            RoundTripWorker worker = new RoundTripWorker(
                process.StandardInput, process.StandardOutput);
            bool failed = false;
            try
            {
                string request;
                while ((request = Console.ReadLine()) != null)
                {
                    string response;
                    try
                    {
                        response = worker.Execute(request,
                            RequestTimeout(request, requestTimeout,
                                syncTimeout));
                        if (response == null)
                        {
                            throw new IOException(description +
                                " exited unexpectedly");
                        }
                    }
                    catch (Exception error)
                    {
                        WriteFatal(new IOException(description +
                            " failed while handling " +
                            RequestCommand(request) + ": " + error.Message,
                            error));
                        failed = true;
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
            }
            finally
            {
                if (failed)
                {
                    Kill(process);
                }
                else
                {
                    try
                    {
                        process.StandardInput.Close();
                    }
                    catch (IOException)
                    {
                        failed = true;
                    }
                }
                if (!process.WaitForExit(requestTimeout))
                {
                    Kill(process);
                    process.WaitForExit(1000);
                    failed = true;
                }
                worker.Stop();
                errorThread.Join(1000);
            }
            return failed ? 1 : process.ExitCode;
        }
    }
}

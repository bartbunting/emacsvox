// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class NativeDectalk
{
    private const string DectalkLibrary = "DECtalk.dll";

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern IntPtr LoadLibrary(string path);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetDllDirectory(string path);

    [DllImport("user32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
    internal static extern uint RegisterWindowMessage(string message);

    [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
    internal delegate void Callback(int parameter1, int parameter2,
        uint userParameter, uint message);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl,
        CharSet = CharSet.Ansi)]
    internal static extern uint TextToSpeechStartupExFonix(out IntPtr handle,
        uint device, uint options, Callback callback, int instanceParameter,
        string dictionaryPath);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechShutdown(IntPtr handle);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechSpeak(IntPtr handle, IntPtr text,
        uint flags);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechPause(IntPtr handle);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechResume(IntPtr handle);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechReset(IntPtr handle,
        [MarshalAs(UnmanagedType.Bool)] bool resetModes);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechSync(IntPtr handle);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechGetRate(IntPtr handle,
        out uint rate);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechSetRate(IntPtr handle, uint rate);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechOpenInMemory(IntPtr handle,
        uint format);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechCloseInMemory(IntPtr handle);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechAddBuffer(IntPtr handle,
        IntPtr buffer);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechVersion(out IntPtr version);
}

[StructLayout(LayoutKind.Sequential)]
internal struct DectalkBuffer
{
    internal IntPtr Data;
    internal IntPtr PhonemeArray;
    internal IntPtr IndexArray;
    internal uint MaximumBufferLength;
    internal uint MaximumPhonemeChanges;
    internal uint MaximumIndexMarks;
    internal uint BufferLength;
    internal uint NumberOfPhonemeChanges;
    internal uint NumberOfIndexMarks;
    internal uint Reserved;
}

internal sealed class DectalkEngine : IDisposable
{
    private sealed class BufferSlot
    {
        internal IntPtr Data;
        internal IntPtr Buffer;
    }

    private const uint WaveMapper = 0xffffffff;
    private const uint DoNotUseAudioDevice = 0x80000000;
    private const uint WaveFormat11025Mono16 = 0x00000004;
    private const uint TtsForce = 1;
    private const int SpeechSampleRate = 11025;
    private const int BufferSamples = 512;
    private const int BufferBytes = BufferSamples * 2;
    private const int BufferCount = 4;

    private readonly object audioLock = new object();
    private readonly object stateLock = new object();
    private readonly Encoding textEncoding;
    private readonly List<BufferSlot> buffers = new List<BufferSlot>();
    private IntPtr handle;
    private NativeDectalk.Callback callback;
    private WaveOutPlayer player;
    private uint bufferMessage;
    private Exception callbackError;
    private bool discardAudio;
    private bool shuttingDown;
    private bool memoryOpen;
    private bool speechStopped = true;

    internal DectalkEngine(string dllPath)
    {
        if (IntPtr.Size != 4)
        {
            throw new InvalidOperationException(
                "DectalkBridge32.exe must run as a 32-bit process");
        }

        dllPath = Path.GetFullPath(dllPath);
        if (!File.Exists(dllPath))
        {
            throw new FileNotFoundException("DECtalk.dll was not found",
                dllPath);
        }

        string directory = Path.GetDirectoryName(dllPath);
        string dictionary = Path.Combine(directory, "dtalk_us.dic");
        if (!File.Exists(dictionary))
        {
            throw new FileNotFoundException("dtalk_us.dic was not found",
                dictionary);
        }

        Environment.CurrentDirectory = directory;
        NativeDectalk.SetDllDirectory(directory);
        if (NativeDectalk.LoadLibrary(dllPath) == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(),
                "Could not load " + dllPath);
        }

        try
        {
            textEncoding = Encoding.GetEncoding(28591,
                EncoderFallback.ExceptionFallback,
                DecoderFallback.ExceptionFallback);
            bufferMessage = NativeDectalk.RegisterWindowMessage(
                "DECtalkBufferMessage");
            if (bufferMessage == 0)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Could not register the DECtalk buffer message");
            }

            callback = OnDectalkCallback;
            Check(NativeDectalk.TextToSpeechStartupExFonix(out handle,
                WaveMapper, DoNotUseAudioDevice, callback, 0, dictionary),
                "TextToSpeechStartupExFonix");
            if (handle == IntPtr.Zero)
            {
                throw new InvalidOperationException(
                    "DECtalk returned a null speech handle");
            }

            player = new WaveOutPlayer(SpeechSampleRate, 1, 16, BufferBytes);
            Check(NativeDectalk.TextToSpeechOpenInMemory(handle,
                WaveFormat11025Mono16), "TextToSpeechOpenInMemory");
            memoryOpen = true;
            AllocateBuffers();
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    internal string Version
    {
        get
        {
            IntPtr value;
            NativeDectalk.TextToSpeechVersion(out value);
            return value == IntPtr.Zero ? "DECtalk Software" :
                Marshal.PtrToStringAnsi(value);
        }
    }

    internal void Speak(string text)
    {
        ThrowCallbackError();
        byte[] bytes = textEncoding.GetBytes(text + "\0");
        GCHandle pinned = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            lock (audioLock)
            {
                player.StartStream();
            }
            Check(NativeDectalk.TextToSpeechSpeak(handle,
                pinned.AddrOfPinnedObject(), TtsForce), "TextToSpeechSpeak");
            speechStopped = false;
        }
        finally
        {
            pinned.Free();
        }
    }

    internal void TypeCharacter(string text)
    {
        if (String.IsNullOrEmpty(text))
        {
            return;
        }
        if (!speechStopped)
        {
            Stop();
        }
        Speak(text.Substring(0, 1));
    }

    internal void Stop()
    {
        SetDiscardAudio(true);
        try
        {
            lock (audioLock)
            {
                player.Stop();
            }
            Check(NativeDectalk.TextToSpeechReset(handle, false),
                "TextToSpeechReset");
            speechStopped = true;
        }
        finally
        {
            SetDiscardAudio(false);
        }
        ClearCallbackError();
    }

    internal void Pause(bool pause)
    {
        Check(pause ? NativeDectalk.TextToSpeechPause(handle) :
            NativeDectalk.TextToSpeechResume(handle),
            pause ? "TextToSpeechPause" : "TextToSpeechResume");
        lock (audioLock)
        {
            player.Pause(pause);
        }
    }

    internal void Synchronize()
    {
        Check(NativeDectalk.TextToSpeechSync(handle), "TextToSpeechSync");
        ThrowCallbackError();
        lock (audioLock)
        {
            player.WaitUntilIdle();
        }
        ThrowCallbackError();
    }

    internal bool Speaking()
    {
        ThrowCallbackError();
        lock (audioLock)
        {
            return player.IsPlaying;
        }
    }

    internal int GetRate()
    {
        uint rate;
        Check(NativeDectalk.TextToSpeechGetRate(handle, out rate),
            "TextToSpeechGetRate");
        return checked((int)rate);
    }

    internal void SetRate(int rate)
    {
        if (rate < 75 || rate > 600)
        {
            throw new ArgumentOutOfRangeException("rate",
                "DECtalk rate must be between 75 and 600 words per minute");
        }
        Check(NativeDectalk.TextToSpeechSetRate(handle, (uint)rate),
            "TextToSpeechSetRate");
    }

    private void AllocateBuffers()
    {
        int structureSize = Marshal.SizeOf(typeof(DectalkBuffer));
        for (int index = 0; index < BufferCount; ++index)
        {
            BufferSlot slot = new BufferSlot();
            slot.Data = Marshal.AllocHGlobal(BufferBytes);
            slot.Buffer = Marshal.AllocHGlobal(structureSize);

            DectalkBuffer buffer = new DectalkBuffer();
            buffer.Data = slot.Data;
            buffer.MaximumBufferLength = BufferBytes;
            Marshal.StructureToPtr(buffer, slot.Buffer, false);
            buffers.Add(slot);
            Check(NativeDectalk.TextToSpeechAddBuffer(handle, slot.Buffer),
                "TextToSpeechAddBuffer");
        }
    }

    private void OnDectalkCallback(int parameter1, int parameter2,
        uint userParameter, uint message)
    {
        if (message != bufferMessage || parameter2 == 0)
        {
            return;
        }

        IntPtr bufferPointer = new IntPtr(parameter2);
        try
        {
            DectalkBuffer buffer = (DectalkBuffer)Marshal.PtrToStructure(
                bufferPointer, typeof(DectalkBuffer));
            if (buffer.BufferLength > BufferBytes ||
                (buffer.BufferLength & 1) != 0)
            {
                throw new InvalidOperationException(
                    "DECtalk returned an invalid PCM buffer length");
            }

            if (buffer.BufferLength > 0 && !ShouldDiscardAudio())
            {
                lock (audioLock)
                {
                    if (!ShouldDiscardAudio())
                    {
                        player.Feed(buffer.Data,
                            checked((int)buffer.BufferLength / 2));
                    }
                }
            }
        }
        catch (Exception error)
        {
            SetCallbackError(error);
        }
        finally
        {
            try
            {
                DectalkBuffer buffer =
                    (DectalkBuffer)Marshal.PtrToStructure(bufferPointer,
                        typeof(DectalkBuffer));
                buffer.BufferLength = 0;
                buffer.NumberOfPhonemeChanges = 0;
                buffer.NumberOfIndexMarks = 0;
                Marshal.StructureToPtr(buffer, bufferPointer, false);
                if (!IsShuttingDown())
                {
                    Check(NativeDectalk.TextToSpeechAddBuffer(handle,
                        bufferPointer), "TextToSpeechAddBuffer");
                }
            }
            catch (Exception error)
            {
                SetCallbackError(error);
            }
        }
    }

    private bool ShouldDiscardAudio()
    {
        lock (stateLock)
        {
            return discardAudio || shuttingDown;
        }
    }

    private bool IsShuttingDown()
    {
        lock (stateLock)
        {
            return shuttingDown;
        }
    }

    private void SetDiscardAudio(bool value)
    {
        lock (stateLock)
        {
            discardAudio = value;
        }
    }

    private void SetCallbackError(Exception error)
    {
        lock (stateLock)
        {
            if (callbackError == null)
            {
                callbackError = error;
            }
        }
    }

    private void ClearCallbackError()
    {
        lock (stateLock)
        {
            callbackError = null;
        }
    }

    private void ThrowCallbackError()
    {
        Exception error;
        lock (stateLock)
        {
            error = callbackError;
            callbackError = null;
        }
        if (error != null)
        {
            throw new InvalidOperationException(
                "Windows PCM playback failed", error);
        }
    }

    private static void Check(uint result, string operation)
    {
        if (result != 0)
        {
            throw new InvalidOperationException(operation +
                " failed with DECtalk error " + result);
        }
    }

    public void Dispose()
    {
        lock (stateLock)
        {
            shuttingDown = true;
            discardAudio = true;
        }

        if (handle != IntPtr.Zero)
        {
            NativeDectalk.TextToSpeechReset(handle, false);
            if (player != null)
            {
                lock (audioLock)
                {
                    player.Stop();
                }
            }
            if (memoryOpen)
            {
                NativeDectalk.TextToSpeechCloseInMemory(handle);
                memoryOpen = false;
            }
            NativeDectalk.TextToSpeechShutdown(handle);
            handle = IntPtr.Zero;
        }

        if (player != null)
        {
            player.Dispose();
            player = null;
        }
        for (int index = 0; index < buffers.Count; ++index)
        {
            if (buffers[index].Buffer != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(buffers[index].Buffer);
            }
            if (buffers[index].Data != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(buffers[index].Data);
            }
        }
        buffers.Clear();
    }
}

internal static class DectalkBridge
{
    private static string Execute(DectalkEngine engine, string command,
        string argument, out bool quit)
    {
        quit = false;
        switch (command)
        {
            case "PING":
                return "OK";
            case "VERSION":
                return "OK " + engine.Version;
            case "SPEAK":
                engine.Speak(WindowsSpeechBridgeProtocol.DecodeText(argument));
                return "OK";
            case "TYPE":
                engine.TypeCharacter(
                    WindowsSpeechBridgeProtocol.DecodeText(argument));
                return "OK";
            case "SPEAKING":
                return engine.Speaking() ? "OK 1" : "OK 0";
            case "STOP":
            case "RESET":
                engine.Stop();
                return "OK";
            case "PAUSE":
                engine.Pause(WindowsSpeechBridgeProtocol.ParseInteger(
                    argument, "pause flag") != 0);
                return "OK";
            case "SYNC":
                engine.Synchronize();
                return "OK";
            case "GET_RATE":
                return "OK " + engine.GetRate();
            case "SET_RATE":
                engine.SetRate(WindowsSpeechBridgeProtocol.ParseInteger(
                    argument, "rate"));
                return "OK";
            case "QUIT":
                quit = true;
                return "OK";
            default:
                throw new ArgumentException("Unknown command: " + command);
        }
    }

    internal static int Main(string[] args)
    {
        string dllPath = args.Length > 0 ? args[0] :
            Environment.GetEnvironmentVariable("EMACSVOX_DECTALK_DLL");
        if (String.IsNullOrEmpty(dllPath))
        {
            dllPath = Path.GetFullPath(Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory, "..", "runtime",
                "DECtalk.dll"));
        }

        try
        {
            using (DectalkEngine engine = new DectalkEngine(dllPath))
            {
                return WindowsSpeechBridgeProtocol.Run(
                    delegate(string command, string argument, out bool quit)
                    {
                        return Execute(engine, command, argument, out quit);
                    });
            }
        }
        catch (Exception error)
        {
            WindowsSpeechBridgeProtocol.WriteError(error);
            return 1;
        }
    }
}

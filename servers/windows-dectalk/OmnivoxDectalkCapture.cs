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

internal static class OmnivoxNativeDectalk
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
    internal static extern uint TextToSpeechReset(IntPtr handle,
        [MarshalAs(UnmanagedType.Bool)] bool resetModes);

    [DllImport(DectalkLibrary, CallingConvention = CallingConvention.Cdecl)]
    internal static extern uint TextToSpeechSync(IntPtr handle);

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
internal struct OmnivoxDectalkBuffer
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

/// <summary>
/// Owns one 32-bit DECtalk instance and captures its in-memory PCM buffers.
/// Phoneme and index arrays are intentionally left disabled until their native
/// structures can be mapped to the versioned marker contract.
/// </summary>
internal sealed class OmnivoxDectalkCapture : IDisposable
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
    private const int BufferSamples = 512;
    private const int BufferBytes = BufferSamples * 2;
    private const int BufferCount = 4;
    private const int MaximumAudioBytes = 128 * 1024 * 1024;
    internal const int SpeechSampleRate = 11025;

    private readonly object synthesisLock = new object();
    private readonly object stateLock = new object();
    private readonly Encoding textEncoding;
    private readonly List<BufferSlot> buffers = new List<BufferSlot>();
    private IntPtr handle;
    private OmnivoxNativeDectalk.Callback callback;
    private uint bufferMessage;
    private MemoryStream capture;
    private Exception callbackError;
    private bool discardAudio;
    private bool shuttingDown;
    private bool memoryOpen;

    internal OmnivoxDectalkCapture(string dllPath)
    {
        if (IntPtr.Size != 4)
        {
            throw new InvalidOperationException(
                "OmnivoxDectalkHelper32.exe must run as a 32-bit process");
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
        OmnivoxNativeDectalk.SetDllDirectory(directory);
        if (OmnivoxNativeDectalk.LoadLibrary(dllPath) == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(),
                "Could not load " + dllPath);
        }

        try
        {
            textEncoding = Encoding.GetEncoding(28591,
                EncoderFallback.ReplacementFallback,
                DecoderFallback.ReplacementFallback);
            bufferMessage = OmnivoxNativeDectalk.RegisterWindowMessage(
                "DECtalkBufferMessage");
            if (bufferMessage == 0)
            {
                throw new Win32Exception(Marshal.GetLastWin32Error(),
                    "Could not register the DECtalk buffer message");
            }

            callback = OnDectalkCallback;
            Check(OmnivoxNativeDectalk.TextToSpeechStartupExFonix(
                out handle, WaveMapper, DoNotUseAudioDevice, callback, 0,
                dictionary), "TextToSpeechStartupExFonix");
            if (handle == IntPtr.Zero)
            {
                throw new InvalidOperationException(
                    "DECtalk returned a null speech handle");
            }
            Check(OmnivoxNativeDectalk.TextToSpeechOpenInMemory(handle,
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
            OmnivoxNativeDectalk.TextToSpeechVersion(out value);
            return value == IntPtr.Zero ? "DECtalk Software" :
                Marshal.PtrToStringAnsi(value);
        }
    }

    internal byte[] Synthesize(string text, string voiceCode, int rate)
    {
        lock (synthesisLock)
        {
            BeginCapture();
            try
            {
                Check(OmnivoxNativeDectalk.TextToSpeechSetRate(handle,
                    (uint)rate), "TextToSpeechSetRate");
                Speak("[" + voiceCode + "] " + text);
                Check(OmnivoxNativeDectalk.TextToSpeechSync(handle),
                    "TextToSpeechSync");
                ThrowCallbackError();
                lock (stateLock)
                {
                    return capture.ToArray();
                }
            }
            finally
            {
                lock (stateLock)
                {
                    if (capture != null)
                    {
                        capture.Dispose();
                        capture = null;
                    }
                }
            }
        }
    }

    internal void Stop()
    {
        lock (stateLock)
        {
            discardAudio = true;
        }
        try
        {
            if (handle != IntPtr.Zero)
            {
                OmnivoxNativeDectalk.TextToSpeechReset(handle, false);
            }
        }
        finally
        {
            lock (stateLock)
            {
                discardAudio = false;
                callbackError = null;
            }
        }
    }

    private void BeginCapture()
    {
        lock (stateLock)
        {
            discardAudio = true;
        }
        Check(OmnivoxNativeDectalk.TextToSpeechReset(handle, false),
            "TextToSpeechReset");
        lock (stateLock)
        {
            callbackError = null;
            if (capture != null)
            {
                capture.Dispose();
            }
            capture = new MemoryStream();
            discardAudio = false;
        }
    }

    private void Speak(string text)
    {
        byte[] bytes = textEncoding.GetBytes(text + "\0");
        GCHandle pinned = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            Check(OmnivoxNativeDectalk.TextToSpeechSpeak(handle,
                pinned.AddrOfPinnedObject(), TtsForce), "TextToSpeechSpeak");
        }
        finally
        {
            pinned.Free();
        }
    }

    private void AllocateBuffers()
    {
        int structureSize = Marshal.SizeOf(typeof(OmnivoxDectalkBuffer));
        for (int index = 0; index < BufferCount; ++index)
        {
            BufferSlot slot = new BufferSlot();
            slot.Data = Marshal.AllocHGlobal(BufferBytes);
            slot.Buffer = Marshal.AllocHGlobal(structureSize);
            OmnivoxDectalkBuffer buffer = new OmnivoxDectalkBuffer();
            buffer.Data = slot.Data;
            buffer.MaximumBufferLength = BufferBytes;
            Marshal.StructureToPtr(buffer, slot.Buffer, false);
            buffers.Add(slot);
            Check(OmnivoxNativeDectalk.TextToSpeechAddBuffer(handle,
                slot.Buffer), "TextToSpeechAddBuffer");
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
            OmnivoxDectalkBuffer buffer =
                (OmnivoxDectalkBuffer)Marshal.PtrToStructure(bufferPointer,
                    typeof(OmnivoxDectalkBuffer));
            if (buffer.BufferLength > BufferBytes ||
                (buffer.BufferLength & 1) != 0)
            {
                throw new InvalidOperationException(
                    "DECtalk returned an invalid PCM buffer length");
            }

            lock (stateLock)
            {
                if (buffer.BufferLength > 0 && !discardAudio &&
                    !shuttingDown)
                {
                    int count = checked((int)buffer.BufferLength);
                    if (capture == null ||
                        capture.Length + count > MaximumAudioBytes)
                    {
                        throw new InvalidOperationException(
                            "DECtalk synthesis exceeded the 128 MiB audio limit");
                    }
                    byte[] bytes = new byte[count];
                    Marshal.Copy(buffer.Data, bytes, 0, count);
                    capture.Write(bytes, 0, count);
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
                OmnivoxDectalkBuffer buffer =
                    (OmnivoxDectalkBuffer)Marshal.PtrToStructure(
                        bufferPointer, typeof(OmnivoxDectalkBuffer));
                buffer.BufferLength = 0;
                buffer.NumberOfPhonemeChanges = 0;
                buffer.NumberOfIndexMarks = 0;
                Marshal.StructureToPtr(buffer, bufferPointer, false);
                if (!IsShuttingDown())
                {
                    Check(OmnivoxNativeDectalk.TextToSpeechAddBuffer(handle,
                        bufferPointer), "TextToSpeechAddBuffer");
                }
            }
            catch (Exception error)
            {
                SetCallbackError(error);
            }
        }
    }

    private bool IsShuttingDown()
    {
        lock (stateLock)
        {
            return shuttingDown;
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
                "DECtalk PCM capture failed", error);
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
            OmnivoxNativeDectalk.TextToSpeechReset(handle, false);
            if (memoryOpen)
            {
                OmnivoxNativeDectalk.TextToSpeechCloseInMemory(handle);
                memoryOpen = false;
            }
            OmnivoxNativeDectalk.TextToSpeechShutdown(handle);
            handle = IntPtr.Zero;
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
        lock (stateLock)
        {
            if (capture != null)
            {
                capture.Dispose();
                capture = null;
            }
        }
    }
}

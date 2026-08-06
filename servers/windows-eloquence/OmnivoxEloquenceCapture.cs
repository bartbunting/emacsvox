// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;

internal static class OmnivoxNativeEci
{
    private const string EciLibrary = "ECI.DLL";

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    internal static extern IntPtr LoadLibrary(string path);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetDllDirectory(string path);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciVersion")]
    internal static extern void Version(StringBuilder buffer);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciNewEx")]
    internal static extern IntPtr NewEx(int languageDialect);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciDelete")]
    internal static extern void Delete(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciStop")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Stop(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciClearInput")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool ClearInput(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSynthesize")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Synthesize(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSynchronize")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Synchronize(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciAddText")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool AddText(IntPtr handle, IntPtr text);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSetParam")]
    internal static extern int SetParam(IntPtr handle, int parameter, int value);

    [UnmanagedFunctionPointer(CallingConvention.StdCall)]
    internal delegate int Callback(IntPtr handle, int message, int parameter,
        IntPtr data);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciRegisterCallback")]
    internal static extern void RegisterCallback(IntPtr handle,
        Callback callback, IntPtr data);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSetOutputBuffer")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetOutputBuffer(IntPtr handle, int samples,
        IntPtr buffer);
}

/// <summary>
/// Owns one 32-bit ECI instance and captures its native mono PCM.  This is
/// deliberately independent of EloquenceEngine, whose callbacks feed waveOut
/// for the existing standalone Emacsvox server.
/// </summary>
internal sealed class OmnivoxEloquenceCapture : IDisposable
{
    private const int GeneralAmericanEnglish = 0x00010000;
    private const int SynthMode = 0;
    private const int InputType = 1;
    private const int SampleRate = 5;
    private const int OutputBufferSamples = 512;
    private const int WaveformBufferMessage = 0;
    private const int CallbackDataProcessed = 1;
    private const int CallbackAbort = 2;
    internal const int SpeechSampleRate = 11025;
    internal const int MaximumAudioBytes = 128 * 1024 * 1024;

    private readonly Encoding textEncoding;
    private readonly object synthesisLock = new object();
    private IntPtr handle;
    private IntPtr outputBuffer;
    private OmnivoxNativeEci.Callback callback;
    private MemoryStream capture;
    private Exception callbackError;

    internal OmnivoxEloquenceCapture(string dllPath)
    {
        if (IntPtr.Size != 4)
        {
            throw new InvalidOperationException(
                "OmnivoxEloquenceHelper32.exe must run as a 32-bit process");
        }

        dllPath = Path.GetFullPath(dllPath);
        if (!File.Exists(dllPath))
        {
            throw new FileNotFoundException("ECI.DLL was not found", dllPath);
        }

        string directory = Path.GetDirectoryName(dllPath);
        Environment.CurrentDirectory = directory;
        OmnivoxNativeEci.SetDllDirectory(directory);
        if (OmnivoxNativeEci.LoadLibrary(dllPath) == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(),
                "Could not load " + dllPath);
        }

        try
        {
            handle = OmnivoxNativeEci.NewEx(GeneralAmericanEnglish);
            if (handle == IntPtr.Zero)
            {
                throw new InvalidOperationException(
                    "ECI could not create an American English engine instance");
            }

            textEncoding = Encoding.GetEncoding(1252,
                EncoderFallback.ReplacementFallback,
                DecoderFallback.ReplacementFallback);
            outputBuffer = Marshal.AllocHGlobal(OutputBufferSamples * 2);
            callback = OnEciCallback;
            OmnivoxNativeEci.RegisterCallback(handle, callback, IntPtr.Zero);
            Configure();
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
            StringBuilder buffer = new StringBuilder(32);
            OmnivoxNativeEci.Version(buffer);
            return buffer.ToString();
        }
    }

    internal byte[] Synthesize(string text, string voiceId, int rate)
    {
        lock (synthesisLock)
        {
            callbackError = null;
            capture = new MemoryStream();
            try
            {
                // A cancelled synthesis can leave queued input behind.  Start
                // every request from a known empty native state.
                OmnivoxNativeEci.Stop(handle);
                Check(OmnivoxNativeEci.ClearInput(handle), "eciClearInput");
                Configure();
                AddText(" `" + voiceId + " `vs" + rate + " " + text);
                Check(OmnivoxNativeEci.Synthesize(handle), "eciSynthesize");
                Check(OmnivoxNativeEci.Synchronize(handle), "eciSynchronize");
                ThrowCallbackError();
                return capture.ToArray();
            }
            finally
            {
                capture.Dispose();
                capture = null;
                OmnivoxNativeEci.ClearInput(handle);
            }
        }
    }

    /// <summary>
    /// Interrupt the ECI synchronization call from the protocol thread.
    /// </summary>
    internal void Stop()
    {
        if (handle != IntPtr.Zero)
        {
            OmnivoxNativeEci.Stop(handle);
        }
    }

    private void AddText(string text)
    {
        byte[] bytes = textEncoding.GetBytes(text + "\0");
        GCHandle pinned = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            Check(OmnivoxNativeEci.AddText(handle,
                pinned.AddrOfPinnedObject()), "eciAddText");
        }
        finally
        {
            pinned.Free();
        }
    }

    private void Configure()
    {
        CheckParameter(OmnivoxNativeEci.SetParam(handle, InputType, 1),
            "eciInputType");
        CheckParameter(OmnivoxNativeEci.SetParam(handle, SynthMode, 1),
            "eciSynthMode");
        CheckParameter(OmnivoxNativeEci.SetParam(handle, SampleRate, 1),
            "eciSampleRate");
        Check(OmnivoxNativeEci.SetOutputBuffer(handle, OutputBufferSamples,
            outputBuffer), "eciSetOutputBuffer");
    }

    private int OnEciCallback(IntPtr callbackHandle, int message,
        int parameter, IntPtr data)
    {
        if (message != WaveformBufferMessage || parameter <= 0)
        {
            return CallbackDataProcessed;
        }
        try
        {
            int byteCount = checked(parameter * 2);
            if (capture == null || capture.Length + byteCount > MaximumAudioBytes)
            {
                throw new InvalidOperationException(
                    "Eloquence synthesis exceeded the 128 MiB audio limit");
            }
            byte[] bytes = new byte[byteCount];
            Marshal.Copy(outputBuffer, bytes, 0, byteCount);
            capture.Write(bytes, 0, bytes.Length);
            return CallbackDataProcessed;
        }
        catch (Exception error)
        {
            callbackError = error;
            return CallbackAbort;
        }
    }

    private void ThrowCallbackError()
    {
        if (callbackError != null)
        {
            Exception error = callbackError;
            callbackError = null;
            throw new InvalidOperationException(
                "Eloquence PCM capture failed", error);
        }
    }

    private static void Check(bool result, string operation)
    {
        if (!result)
        {
            throw new InvalidOperationException(operation + " failed");
        }
    }

    private static void CheckParameter(int result, string parameter)
    {
        if (result == -1)
        {
            throw new InvalidOperationException(
                "eciSetParam failed for " + parameter);
        }
    }

    public void Dispose()
    {
        if (handle != IntPtr.Zero)
        {
            OmnivoxNativeEci.Stop(handle);
            OmnivoxNativeEci.Delete(handle);
            handle = IntPtr.Zero;
        }
        if (outputBuffer != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(outputBuffer);
            outputBuffer = IntPtr.Zero;
        }
        if (capture != null)
        {
            capture.Dispose();
            capture = null;
        }
    }
}

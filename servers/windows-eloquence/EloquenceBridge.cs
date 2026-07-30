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

internal static class NativeEci
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
        EntryPoint = "eciReset")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Reset(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciStop")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Stop(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciClearInput")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool ClearInput(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciPause")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Pause(IntPtr handle, int pause);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSynthesize")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Synthesize(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSynchronize")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Synchronize(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSpeaking")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool Speaking(IntPtr handle);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciAddText")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool AddText(IntPtr handle, IntPtr text);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciInsertIndex")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool InsertIndex(IntPtr handle, int index);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSetParam")]
    internal static extern int SetParam(IntPtr handle, int parameter, int value);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciGetVoiceParam")]
    internal static extern int GetVoiceParam(IntPtr handle, int voice,
        int parameter);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSetVoiceParam")]
    internal static extern int SetVoiceParam(IntPtr handle, int voice,
        int parameter, int value);

    [DllImport(EciLibrary, CallingConvention = CallingConvention.StdCall,
        EntryPoint = "eciSetOutputDevice")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool SetOutputDevice(IntPtr handle, int device);

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

internal sealed class EloquenceEngine : IDisposable
{
    private sealed class IndexedTone
    {
        internal int Frequency;
        internal int DurationMilliseconds;
    }

    private const int GeneralAmericanEnglish = 0x00010000;
    private const int SynthMode = 0;
    private const int InputType = 1;
    private const int SampleRate = 5;
    private const int VoiceSpeed = 6;
    private const int OutputBufferSamples = 512;
    private const int SpeechSampleRate = 11025;
    private const int ToneSampleRate = 48000;
    private const int MaximumToneMilliseconds = 2000;
    private const int FirstToneIndex = 0x40000000;
    private const int WaveformBufferMessage = 0;
    private const int IndexReplyMessage = 2;
    private const int EndOfUtteranceIndex = 0xffff;
    private const int CallbackDataProcessed = 1;
    private const int CallbackAbort = 2;

    private readonly Encoding textEncoding;
    private IntPtr handle;
    private IntPtr outputBuffer;
    private NativeEci.Callback callback;
    private WaveOutPlayer player;
    private WaveOutPlayer tonePlayer;
    private Exception callbackError;
    private int pendingSyntheses;
    private int nextToneIndex = FirstToneIndex;
    private readonly Dictionary<int, IndexedTone> indexedTones =
        new Dictionary<int, IndexedTone>();

    internal EloquenceEngine(string dllPath)
    {
        if (IntPtr.Size != 4)
        {
            throw new InvalidOperationException(
                "EloquenceBridge32.exe must run as a 32-bit process");
        }

        dllPath = Path.GetFullPath(dllPath);
        if (!File.Exists(dllPath))
        {
            throw new FileNotFoundException("ECI.DLL was not found", dllPath);
        }

        string directory = Path.GetDirectoryName(dllPath);
        Environment.CurrentDirectory = directory;
        NativeEci.SetDllDirectory(directory);
        if (NativeEci.LoadLibrary(dllPath) == IntPtr.Zero)
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(),
                "Could not load " + dllPath);
        }

        try
        {
            handle = NativeEci.NewEx(GeneralAmericanEnglish);
            if (handle == IntPtr.Zero)
            {
                throw new InvalidOperationException(
                    "ECI could not create an American English engine instance");
            }

            textEncoding = Encoding.GetEncoding(1252,
                EncoderFallback.ReplacementFallback,
                DecoderFallback.ReplacementFallback);
            outputBuffer = Marshal.AllocHGlobal(OutputBufferSamples * 2);
            player = new WaveOutPlayer(SpeechSampleRate, 1, 16,
                OutputBufferSamples * 2);
            tonePlayer = new WaveOutPlayer(ToneSampleRate, 1, 16,
                ToneSampleRate * 2 * MaximumToneMilliseconds / 1000);
            callback = OnEciCallback;
            NativeEci.RegisterCallback(handle, callback, IntPtr.Zero);
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
            NativeEci.Version(buffer);
            return buffer.ToString();
        }
    }

    internal void AddText(string text)
    {
        byte[] bytes = textEncoding.GetBytes(text + "\0");
        GCHandle pinned = GCHandle.Alloc(bytes, GCHandleType.Pinned);
        try
        {
            Check(NativeEci.AddText(handle, pinned.AddrOfPinnedObject()),
                "eciAddText");
        }
        finally
        {
            pinned.Free();
        }
    }

    internal void Synthesize()
    {
        callbackError = null;
        player.StartStream();
        Check(NativeEci.InsertIndex(handle, EndOfUtteranceIndex),
            "eciInsertIndex");
        ++pendingSyntheses;
        try
        {
            Check(NativeEci.Synthesize(handle), "eciSynthesize");
        }
        catch
        {
            --pendingSyntheses;
            throw;
        }
    }

    internal bool Speaking()
    {
        // Polling ECI pumps waveform and index callbacks.  Its Boolean return
        // can remain true after buffered synthesis completes, so use the
        // explicit end marker plus the Windows playback queue as truth.
        NativeEci.Speaking(handle);
        ThrowCallbackError();
        return pendingSyntheses > 0 || player.IsPlaying ||
            tonePlayer.IsPlaying;
    }

    internal void Stop()
    {
        Check(NativeEci.Stop(handle), "eciStop");
        player.Stop();
        tonePlayer.Stop();
        indexedTones.Clear();
        callbackError = null;
        pendingSyntheses = 0;
        Configure();
    }

    internal void StopSpeech()
    {
        Check(NativeEci.Stop(handle), "eciStop");
        player.Stop();
        indexedTones.Clear();
        callbackError = null;
        pendingSyntheses = 0;
        Configure();
    }

    internal void Pause(bool pause)
    {
        Check(NativeEci.Pause(handle, pause ? 1 : 0), "eciPause");
        player.Pause(pause);
        tonePlayer.Pause(pause);
    }

    internal void Synchronize()
    {
        Check(NativeEci.Synchronize(handle), "eciSynchronize");
        ThrowCallbackError();
        player.WaitUntilIdle();
        tonePlayer.WaitUntilIdle();
    }

    internal void Reset()
    {
        Check(NativeEci.Stop(handle), "eciStop");
        player.Stop();
        tonePlayer.Stop();
        indexedTones.Clear();
        Check(NativeEci.Reset(handle), "eciReset");
        callbackError = null;
        pendingSyntheses = 0;
        Configure();
    }

    internal void InsertIndex(int index)
    {
        Check(NativeEci.InsertIndex(handle, index), "eciInsertIndex");
    }

    internal void PlayTone(int frequency, int durationMilliseconds)
    {
        tonePlayer.Stop();
        tonePlayer.PlayTone(frequency, durationMilliseconds);
    }

    internal void InsertTone(int frequency, int durationMilliseconds)
    {
        if (frequency <= 0 || frequency >= SpeechSampleRate / 2)
        {
            throw new ArgumentOutOfRangeException("frequency");
        }
        int sampleCount = checked(
            (SpeechSampleRate * durationMilliseconds + 999) / 1000);
        if (durationMilliseconds <= 0 || sampleCount > OutputBufferSamples)
        {
            throw new ArgumentOutOfRangeException("durationMilliseconds");
        }

        int index = nextToneIndex++;
        IndexedTone tone = new IndexedTone();
        tone.Frequency = frequency;
        tone.DurationMilliseconds = durationMilliseconds;
        indexedTones.Add(index, tone);
        try
        {
            Check(NativeEci.InsertIndex(handle, index), "eciInsertIndex");
        }
        catch
        {
            indexedTones.Remove(index);
            throw;
        }
    }

    internal void SetRate(int voice, int rate)
    {
        int result = NativeEci.SetVoiceParam(handle, voice, VoiceSpeed, rate);
        if (result == -1)
        {
            throw new InvalidOperationException("eciSetVoiceParam failed");
        }
    }

    internal int GetRate(int voice)
    {
        int result = NativeEci.GetVoiceParam(handle, voice, VoiceSpeed);
        if (result == -1)
        {
            throw new InvalidOperationException("eciGetVoiceParam failed");
        }
        return result;
    }

    private void Configure()
    {
        CheckParameter(NativeEci.SetParam(handle, InputType, 1),
            "eciInputType");
        CheckParameter(NativeEci.SetParam(handle, SynthMode, 1),
            "eciSynthMode");
        CheckParameter(NativeEci.SetParam(handle, SampleRate, 1),
            "eciSampleRate");
        Check(NativeEci.SetOutputBuffer(handle, OutputBufferSamples,
            outputBuffer), "eciSetOutputBuffer");
    }

    private int OnEciCallback(IntPtr callbackHandle, int message,
        int parameter, IntPtr data)
    {
        if (message == IndexReplyMessage && parameter == EndOfUtteranceIndex)
        {
            if (pendingSyntheses > 0)
            {
                --pendingSyntheses;
            }
            return CallbackDataProcessed;
        }
        IndexedTone tone;
        if (message == IndexReplyMessage &&
            indexedTones.TryGetValue(parameter, out tone))
        {
            indexedTones.Remove(parameter);
            try
            {
                player.QueueTone(tone.Frequency, tone.DurationMilliseconds);
                return CallbackDataProcessed;
            }
            catch (Exception error)
            {
                callbackError = error;
                return CallbackAbort;
            }
        }
        if (message != WaveformBufferMessage || parameter <= 0)
        {
            return CallbackDataProcessed;
        }
        try
        {
            player.Feed(outputBuffer, parameter);
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
                "Windows PCM playback failed", error);
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
            NativeEci.Stop(handle);
            if (player != null)
            {
                player.Stop();
            }
            if (tonePlayer != null)
            {
                tonePlayer.Stop();
            }
            NativeEci.Delete(handle);
            handle = IntPtr.Zero;
        }
        if (player != null)
        {
            player.Dispose();
            player = null;
        }
        if (tonePlayer != null)
        {
            tonePlayer.Dispose();
            tonePlayer = null;
        }
        if (outputBuffer != IntPtr.Zero)
        {
            Marshal.FreeHGlobal(outputBuffer);
            outputBuffer = IntPtr.Zero;
        }
    }
}

internal static class EloquenceBridge
{
    private const string DefaultDll =
        @"C:\Program Files (x86)\Freedom Scientific\Shared\Eloquence\6.1\ECI.DLL";

    private static string Execute(EloquenceEngine engine, string command,
        string argument, out bool quit)
    {
        quit = false;

        switch (command)
        {
            case "PING":
                return "OK";
            case "VERSION":
                return "OK " + engine.Version;
            case "ADD":
                engine.AddText(WindowsSpeechBridgeProtocol.DecodeText(argument));
                return "OK";
            case "SYNTH":
                engine.Synthesize();
                return "OK";
            case "SPEAKING":
                return engine.Speaking() ? "OK 1" : "OK 0";
            case "STOP":
                engine.Stop();
                return "OK";
            case "STOP_SPEECH":
                engine.StopSpeech();
                return "OK";
            case "PAUSE":
                engine.Pause(WindowsSpeechBridgeProtocol.ParseInteger(
                    argument, "pause flag") != 0);
                return "OK";
            case "SYNC":
                engine.Synchronize();
                return "OK";
            case "RESET":
                engine.Reset();
                return "OK";
            case "INDEX":
                engine.InsertIndex(WindowsSpeechBridgeProtocol.ParseInteger(
                    argument, "index"));
                return "OK";
            case "TONE":
                string[] toneValues = argument.Split(new char[] { ' ' },
                    StringSplitOptions.RemoveEmptyEntries);
                if (toneValues.Length != 2)
                {
                    throw new ArgumentException(
                        "TONE requires frequency and duration");
                }
                engine.PlayTone(WindowsSpeechBridgeProtocol.ParseInteger(
                    toneValues[0], "frequency"),
                    WindowsSpeechBridgeProtocol.ParseInteger(
                        toneValues[1], "duration"));
                return "OK";
            case "INDEX_TONE":
                string[] indexedToneValues = argument.Split(
                    new char[] { ' ' },
                    StringSplitOptions.RemoveEmptyEntries);
                if (indexedToneValues.Length != 2)
                {
                    throw new ArgumentException(
                        "INDEX_TONE requires frequency and duration");
                }
                engine.InsertTone(
                    WindowsSpeechBridgeProtocol.ParseInteger(
                        indexedToneValues[0], "frequency"),
                    WindowsSpeechBridgeProtocol.ParseInteger(
                        indexedToneValues[1], "duration"));
                return "OK";
            case "GET_RATE":
                return "OK " + engine.GetRate(
                    WindowsSpeechBridgeProtocol.ParseInteger(
                        argument, "voice"));
            case "SET_RATE":
                string[] values = argument.Split(new char[] { ' ' },
                    StringSplitOptions.RemoveEmptyEntries);
                if (values.Length != 2)
                {
                    throw new ArgumentException(
                        "SET_RATE requires voice and rate");
                }
                engine.SetRate(WindowsSpeechBridgeProtocol.ParseInteger(
                    values[0], "voice"),
                    WindowsSpeechBridgeProtocol.ParseInteger(
                        values[1], "rate"));
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
            Environment.GetEnvironmentVariable("EMACSVOX_ECI_DLL");
        if (String.IsNullOrEmpty(dllPath))
        {
            dllPath = DefaultDll;
        }

        try
        {
            using (EloquenceEngine engine = new EloquenceEngine(dllPath))
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

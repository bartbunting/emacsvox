// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Globalization;
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
        EntryPoint = "eciInsertIndex")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool InsertIndex(IntPtr handle, int index);

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
    private sealed class MarkerInsertion
    {
        internal int Position;
        internal int Priority;
        internal int Sequence;
        internal OmnivoxHelperMarker Marker;
    }

    private const int GeneralAmericanEnglish = 0x00010000;
    private const int SynthMode = 0;
    private const int InputType = 1;
    private const int SampleRate = 5;
    private const int OutputBufferSamples = 512;
    private const int WaveformBufferMessage = 0;
    private const int IndexReplyMessage = 2;
    private const int CallbackDataProcessed = 1;
    private const int CallbackAbort = 2;
    private const int FirstMarkerIndex = 1;
    private const int MaximumMarkers = 4096;
    private const int MaximumMarkerValueBytes = 16 * 1024;
    internal const int SpeechSampleRate = 11025;
    internal const int MaximumAudioBytes = 128 * 1024 * 1024;

    private readonly Encoding textEncoding;
    private readonly object synthesisLock = new object();
    private IntPtr handle;
    private IntPtr outputBuffer;
    private OmnivoxNativeEci.Callback callback;
    private MemoryStream capture;
    private Dictionary<int, OmnivoxHelperMarker> pendingMarkers;
    private List<OmnivoxHelperMarker> reachedMarkers;
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

    internal OmnivoxCaptureResult Synthesize(string text, string voiceId,
        int rate, int pitch, int volume, OmnivoxHelperAnchor[] anchors)
    {
        lock (synthesisLock)
        {
            callbackError = null;
            capture = new MemoryStream();
            pendingMarkers = new Dictionary<int, OmnivoxHelperMarker>();
            reachedMarkers = new List<OmnivoxHelperMarker>();
            try
            {
                // A cancelled synthesis can leave queued input behind.  Start
                // every request from a known empty native state.
                OmnivoxNativeEci.Stop(handle);
                Check(OmnivoxNativeEci.ClearInput(handle), "eciClearInput");
                Configure();
                AddText(" `" + voiceId + " `vs" +
                    rate.ToString(CultureInfo.InvariantCulture) + " `vb" +
                    pitch.ToString(CultureInfo.InvariantCulture) + " `vv" +
                    volume.ToString(CultureInfo.InvariantCulture) + " ");
                AddTextWithIndexes(text, anchors);
                Check(OmnivoxNativeEci.Synthesize(handle), "eciSynthesize");
                Check(OmnivoxNativeEci.Synchronize(handle), "eciSynchronize");
                ThrowCallbackError();
                return new OmnivoxCaptureResult(capture.ToArray(),
                    reachedMarkers.ToArray());
            }
            finally
            {
                capture.Dispose();
                capture = null;
                pendingMarkers = null;
                reachedMarkers = null;
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

    private void AddTextWithIndexes(string text,
        OmnivoxHelperAnchor[] anchors)
    {
        List<MarkerInsertion> insertions = new List<MarkerInsertion>();
        int sequence = 0;
        foreach (OmnivoxHelperAnchor anchor in anchors)
        {
            insertions.Add(new MarkerInsertion
            {
                Position = Utf8OffsetToCharPosition(text, anchor.TextOffset),
                Priority = anchor.Affinity == "before" ? 0 : 3,
                Sequence = sequence++,
                Marker = new OmnivoxHelperMarker("requested_anchor", 0,
                    anchor.TextOffset, 0, anchor.Id)
            });
        }

        foreach (OmnivoxTextSpan sentence in
            OmnivoxTextBoundaries.Sentences(text))
        {
            if (insertions.Count >= MaximumMarkers)
            {
                break;
            }
            uint textStart = checked((uint)Encoding.UTF8.GetByteCount(
                text.Substring(0, sentence.Start)));
            uint textLength = checked((uint)Encoding.UTF8.GetByteCount(
                text.Substring(sentence.Start, sentence.Length)));
            insertions.Add(new MarkerInsertion
            {
                Position = sentence.Start,
                Priority = 1,
                Sequence = sequence++,
                Marker = new OmnivoxHelperMarker("sentence", 0,
                    textStart, textLength, null)
            });
        }

        int position = 0;
        while (position < text.Length && insertions.Count < MaximumMarkers)
        {
            int scalarLength;
            if (!IsWordCore(text, position, out scalarLength))
            {
                position += scalarLength;
                continue;
            }

            int wordStart = position;
            position += scalarLength;
            while (position < text.Length)
            {
                if (IsWordCore(text, position, out scalarLength))
                {
                    position += scalarLength;
                    continue;
                }
                if (IsInnerWordConnector(text, position, out scalarLength) &&
                    position + scalarLength < text.Length)
                {
                    int nextLength;
                    if (IsWordCore(text, position + scalarLength,
                        out nextLength))
                    {
                        position += scalarLength + nextLength;
                        continue;
                    }
                }
                break;
            }

            int wordLength = position - wordStart;
            uint textStart = checked((uint)Encoding.UTF8.GetByteCount(
                text.Substring(0, wordStart)));
            uint textLength = checked((uint)Encoding.UTF8.GetByteCount(
                text.Substring(wordStart, wordLength)));
            string value = text.Substring(wordStart, wordLength);
            if (Encoding.UTF8.GetByteCount(value) > MaximumMarkerValueBytes)
            {
                value = null;
            }
            insertions.Add(new MarkerInsertion
            {
                Position = wordStart,
                Priority = 2,
                Sequence = sequence++,
                Marker = new OmnivoxHelperMarker("word", 0, textStart,
                    textLength, value)
            });
        }

        insertions.Sort(delegate(MarkerInsertion left,
            MarkerInsertion right)
        {
            int order = left.Position.CompareTo(right.Position);
            if (order == 0)
            {
                order = left.Priority.CompareTo(right.Priority);
            }
            return order == 0 ? left.Sequence.CompareTo(right.Sequence) :
                order;
        });

        int cursor = 0;
        int markerIndex = FirstMarkerIndex;
        foreach (MarkerInsertion insertion in insertions)
        {
            AddTextSegment(text, cursor, insertion.Position - cursor);
            Check(OmnivoxNativeEci.InsertIndex(handle, markerIndex),
                "eciInsertIndex");
            pendingMarkers.Add(markerIndex++, insertion.Marker);
            cursor = insertion.Position;
        }
        AddTextSegment(text, cursor, text.Length - cursor);
    }

    private static int Utf8OffsetToCharPosition(string text,
        uint targetOffset)
    {
        uint byteOffset = 0;
        int position = 0;
        while (position < text.Length)
        {
            if (byteOffset == targetOffset)
            {
                return position;
            }
            int length = Char.IsHighSurrogate(text[position]) &&
                position + 1 < text.Length &&
                Char.IsLowSurrogate(text[position + 1]) ? 2 : 1;
            byteOffset = checked(byteOffset +
                (uint)Encoding.UTF8.GetByteCount(
                    text.Substring(position, length)));
            position += length;
        }
        if (byteOffset == targetOffset)
        {
            return position;
        }
        throw new ArgumentException("anchor is not on a UTF-8 boundary",
            "targetOffset");
    }

    private void AddTextSegment(string text, int start, int length)
    {
        if (length > 0)
        {
            AddText(text.Substring(start, length));
        }
    }

    private static bool IsWordCore(string text, int position,
        out int scalarLength)
    {
        scalarLength = Char.IsHighSurrogate(text[position]) &&
            position + 1 < text.Length &&
            Char.IsLowSurrogate(text[position + 1]) ? 2 : 1;
        switch (CharUnicodeInfo.GetUnicodeCategory(text, position))
        {
            case UnicodeCategory.UppercaseLetter:
            case UnicodeCategory.LowercaseLetter:
            case UnicodeCategory.TitlecaseLetter:
            case UnicodeCategory.ModifierLetter:
            case UnicodeCategory.OtherLetter:
            case UnicodeCategory.NonSpacingMark:
            case UnicodeCategory.SpacingCombiningMark:
            case UnicodeCategory.DecimalDigitNumber:
            case UnicodeCategory.LetterNumber:
            case UnicodeCategory.OtherNumber:
            case UnicodeCategory.ConnectorPunctuation:
                return true;
            default:
                return false;
        }
    }

    private static bool IsInnerWordConnector(string text, int position,
        out int scalarLength)
    {
        scalarLength = 1;
        char value = text[position];
        return value == '\'' || value == '\u2019' || value == '-';
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
        if (message == IndexReplyMessage)
        {
            OmnivoxHelperMarker marker;
            if (capture != null && pendingMarkers != null &&
                pendingMarkers.TryGetValue(parameter, out marker))
            {
                pendingMarkers.Remove(parameter);
                marker.FrameOffset = (ulong)(capture.Length / 2);
                reachedMarkers.Add(marker);
            }
            return CallbackDataProcessed;
        }
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

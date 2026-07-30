// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Threading;

internal static class NativeWaveOut
{
    internal const uint WaveMapper = 0xffffffff;
    internal const uint CallbackEvent = 0x00050000;
    internal const uint HeaderDone = 0x00000001;

    [StructLayout(LayoutKind.Sequential, Pack = 2)]
    internal struct WaveFormat
    {
        internal ushort FormatTag;
        internal ushort Channels;
        internal uint SamplesPerSecond;
        internal uint AverageBytesPerSecond;
        internal ushort BlockAlign;
        internal ushort BitsPerSample;
        internal ushort ExtraSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct WaveHeader
    {
        internal IntPtr Data;
        internal uint BufferLength;
        internal uint BytesRecorded;
        internal UIntPtr User;
        internal uint Flags;
        internal uint Loops;
        internal IntPtr Next;
        internal UIntPtr Reserved;
    }

    [DllImport("winmm.dll", CallingConvention = CallingConvention.Winapi)]
    internal static extern int waveOutOpen(out IntPtr handle, uint device,
        ref WaveFormat format, IntPtr callback, IntPtr instance, uint flags);

    [DllImport("winmm.dll", CallingConvention = CallingConvention.Winapi)]
    internal static extern int waveOutPrepareHeader(IntPtr handle,
        IntPtr header, uint headerSize);

    [DllImport("winmm.dll", CallingConvention = CallingConvention.Winapi)]
    internal static extern int waveOutUnprepareHeader(IntPtr handle,
        IntPtr header, uint headerSize);

    [DllImport("winmm.dll", CallingConvention = CallingConvention.Winapi)]
    internal static extern int waveOutWrite(IntPtr handle, IntPtr header,
        uint headerSize);

    [DllImport("winmm.dll", CallingConvention = CallingConvention.Winapi)]
    internal static extern int waveOutReset(IntPtr handle);

    [DllImport("winmm.dll", CallingConvention = CallingConvention.Winapi)]
    internal static extern int waveOutPause(IntPtr handle);

    [DllImport("winmm.dll", CallingConvention = CallingConvention.Winapi)]
    internal static extern int waveOutRestart(IntPtr handle);

    [DllImport("winmm.dll", CallingConvention = CallingConvention.Winapi)]
    internal static extern int waveOutClose(IntPtr handle);

}

internal sealed class WaveOutPlayer : IDisposable
{
    private sealed class BufferSlot
    {
        internal IntPtr Data;
        internal IntPtr Header;
        internal bool InUse;
    }

    private const int BufferCount = 3;
    private const int SilenceThreshold = 8;
    private const int LeadingAudioPrerollSamples = 16;
    private const int FullGain = 32768;
    private const string PanEnvironmentVariable =
        "EMACSVOX_WINDOWS_SPEECH_PAN";

    private readonly object syncRoot = new object();
    private readonly AutoResetEvent bufferChanged = new AutoResetEvent(false);
    private readonly BufferSlot[] buffers;
    private readonly int sampleRate;
    private readonly int sourceBufferCapacity;
    private readonly int bufferCapacity;
    private readonly int leftGain;
    private readonly int rightGain;
    private readonly uint headerSize;
    private IntPtr handle;
    private int pendingBuffers;
    private bool trimLeadingSilence;

    internal WaveOutPlayer(int sampleRate, int channels, int bitsPerSample,
        int bufferCapacityBytes)
    {
        if (channels != 1 || bitsPerSample != 16)
        {
            throw new ArgumentException(
                "Stereo positioning requires 16-bit mono source audio");
        }

        this.sampleRate = sampleRate;
        sourceBufferCapacity = bufferCapacityBytes;
        bufferCapacity = checked(bufferCapacityBytes * 2);
        SetPanGains(ReadPan(), out leftGain, out rightGain);
        headerSize = (uint)Marshal.SizeOf(typeof(NativeWaveOut.WaveHeader));
        buffers = new BufferSlot[BufferCount];

        NativeWaveOut.WaveFormat format = new NativeWaveOut.WaveFormat();
        format.FormatTag = 1;
        format.Channels = 2;
        format.SamplesPerSecond = (uint)sampleRate;
        format.BitsPerSample = (ushort)bitsPerSample;
        format.BlockAlign = (ushort)(2 * bitsPerSample / 8);
        format.AverageBytesPerSecond =
            format.SamplesPerSecond * format.BlockAlign;
        format.ExtraSize = 0;

        int result = NativeWaveOut.waveOutOpen(out handle,
            NativeWaveOut.WaveMapper, ref format,
            bufferChanged.SafeWaitHandle.DangerousGetHandle(), IntPtr.Zero,
            NativeWaveOut.CallbackEvent);
        Check(result, "waveOutOpen");

        try
        {
            for (int index = 0; index < buffers.Length; ++index)
            {
                BufferSlot slot = new BufferSlot();
                slot.Data = Marshal.AllocHGlobal(bufferCapacity);
                slot.Header = Marshal.AllocHGlobal((int)headerSize);
                buffers[index] = slot;
            }
        }
        catch
        {
            Dispose();
            throw;
        }
    }

    internal void StartStream()
    {
        trimLeadingSilence = true;
    }

    internal void PlayTone(int frequency, int durationMilliseconds)
    {
        GenerateTone(frequency, durationMilliseconds, false);
    }

    internal void QueueTone(int frequency, int durationMilliseconds)
    {
        GenerateTone(frequency, durationMilliseconds, true);
    }

    private void GenerateTone(int frequency, int durationMilliseconds,
        bool preserveLeadingSilenceState)
    {
        if (frequency <= 0 || frequency >= sampleRate / 2)
        {
            throw new ArgumentOutOfRangeException("frequency");
        }
        if (durationMilliseconds <= 0)
        {
            throw new ArgumentOutOfRangeException("durationMilliseconds");
        }

        int sampleCount = checked(
            (sampleRate * durationMilliseconds + 999) / 1000);

        const double amplitude = 0.40 * Int16.MaxValue;
        int fadeSamples = Math.Min(sampleCount / 2, sampleRate / 200);
        short[] samples = new short[sampleCount];
        for (int index = 0; index < sampleCount; ++index)
        {
            double envelope = 1.0;
            if (fadeSamples > 0 && index < fadeSamples)
            {
                envelope = Math.Sin(Math.PI * index / (2 * fadeSamples));
            }
            else if (fadeSamples > 0 && index >= sampleCount - fadeSamples)
            {
                envelope = Math.Sin(Math.PI * (sampleCount - 1 - index) /
                    (2 * fadeSamples));
            }
            samples[index] = (short)Math.Round(amplitude * envelope *
                Math.Sin(2 * Math.PI * frequency * index / sampleRate));
        }

        GCHandle pinned = GCHandle.Alloc(samples, GCHandleType.Pinned);
        bool savedTrimLeadingSilence = trimLeadingSilence;
        try
        {
            StartStream();
            int maximumChunkSamples = sourceBufferCapacity / 2;
            for (int offset = 0; offset < sampleCount;
                offset += maximumChunkSamples)
            {
                int chunkSamples = Math.Min(
                    maximumChunkSamples, sampleCount - offset);
                Feed(
                    IntPtr.Add(pinned.AddrOfPinnedObject(), offset * 2),
                    chunkSamples);
            }
        }
        finally
        {
            if (preserveLeadingSilenceState)
            {
                trimLeadingSilence = savedTrimLeadingSilence;
            }
            pinned.Free();
        }
    }

    internal void Feed(IntPtr source, int sampleCount)
    {
        int sourceByteCount = checked(sampleCount * 2);
        if (sourceByteCount <= 0)
        {
            return;
        }
        if (sourceByteCount > sourceBufferCapacity)
        {
            throw new InvalidOperationException(
                "Speech engine returned more PCM data than the playback buffer can hold");
        }

        if (trimLeadingSilence)
        {
            int firstAudioSample = FindFirstAudioSample(source, sampleCount);
            if (firstAudioSample == sampleCount)
            {
                return;
            }
            firstAudioSample = Math.Max(0,
                firstAudioSample - LeadingAudioPrerollSamples);
            source = IntPtr.Add(source, firstAudioSample * 2);
            sampleCount -= firstAudioSample;
            trimLeadingSilence = false;
        }

        int byteCount = checked(sampleCount * 4);
        BufferSlot buffer = AcquireBuffer();
        CopyPannedSamples(buffer.Data, source, sampleCount);

        NativeWaveOut.WaveHeader header = new NativeWaveOut.WaveHeader();
        header.Data = buffer.Data;
        header.BufferLength = (uint)byteCount;
        Marshal.StructureToPtr(header, buffer.Header, false);

        try
        {
            Check(NativeWaveOut.waveOutPrepareHeader(handle, buffer.Header,
                headerSize), "waveOutPrepareHeader");
            Check(NativeWaveOut.waveOutWrite(handle, buffer.Header, headerSize),
                "waveOutWrite");
            lock (syncRoot)
            {
                buffer.InUse = true;
                ++pendingBuffers;
            }
        }
        catch
        {
            NativeWaveOut.waveOutUnprepareHeader(handle, buffer.Header,
                headerSize);
            lock (syncRoot)
            {
                buffer.InUse = false;
            }
            throw;
        }
    }

    internal bool IsPlaying
    {
        get
        {
            lock (syncRoot)
            {
                ReclaimCompletedBuffers();
                return pendingBuffers > 0;
            }
        }
    }

    internal void Stop()
    {
        if (handle == IntPtr.Zero)
        {
            return;
        }
        Check(NativeWaveOut.waveOutReset(handle), "waveOutReset");
        lock (syncRoot)
        {
            ReclaimAllBuffers();
            trimLeadingSilence = true;
        }
    }

    internal void Pause(bool pause)
    {
        Check(pause ? NativeWaveOut.waveOutPause(handle) :
            NativeWaveOut.waveOutRestart(handle),
            pause ? "waveOutPause" : "waveOutRestart");
    }

    internal void WaitUntilIdle()
    {
        while (IsPlaying)
        {
            bufferChanged.WaitOne(10);
        }
    }

    private BufferSlot AcquireBuffer()
    {
        DateTime deadline = DateTime.UtcNow.AddSeconds(5);
        while (true)
        {
            lock (syncRoot)
            {
                ReclaimCompletedBuffers();
                for (int index = 0; index < buffers.Length; ++index)
                {
                    if (!buffers[index].InUse)
                    {
                        return buffers[index];
                    }
                }
            }
            if (DateTime.UtcNow >= deadline)
            {
                throw new TimeoutException(
                    "Timed out waiting for a Windows audio buffer");
            }
            bufferChanged.WaitOne(10);
        }
    }

    private void ReclaimCompletedBuffers()
    {
        for (int index = 0; index < buffers.Length; ++index)
        {
            BufferSlot slot = buffers[index];
            if (slot == null || !slot.InUse)
            {
                continue;
            }
            NativeWaveOut.WaveHeader header =
                (NativeWaveOut.WaveHeader)Marshal.PtrToStructure(
                    slot.Header, typeof(NativeWaveOut.WaveHeader));
            if ((header.Flags & NativeWaveOut.HeaderDone) == 0)
            {
                continue;
            }
            Check(NativeWaveOut.waveOutUnprepareHeader(handle, slot.Header,
                headerSize), "waveOutUnprepareHeader");
            slot.InUse = false;
            --pendingBuffers;
        }
    }

    private void ReclaimAllBuffers()
    {
        for (int index = 0; index < buffers.Length; ++index)
        {
            BufferSlot slot = buffers[index];
            if (slot == null || !slot.InUse)
            {
                continue;
            }
            Check(NativeWaveOut.waveOutUnprepareHeader(handle, slot.Header,
                headerSize), "waveOutUnprepareHeader");
            slot.InUse = false;
        }
        pendingBuffers = 0;
    }

    private static int FindFirstAudioSample(IntPtr source, int sampleCount)
    {
        for (int index = 0; index < sampleCount; ++index)
        {
            int sample = Marshal.ReadInt16(source, index * 2);
            if (sample > SilenceThreshold || sample < -SilenceThreshold)
            {
                return index;
            }
        }
        return sampleCount;
    }

    private void CopyPannedSamples(IntPtr destination, IntPtr source,
        int sampleCount)
    {
        for (int index = 0; index < sampleCount; ++index)
        {
            int sample = Marshal.ReadInt16(source, index * 2);
            int outputOffset = index * 4;
            Marshal.WriteInt16(destination, outputOffset,
                (short)(sample * leftGain / FullGain));
            Marshal.WriteInt16(destination, outputOffset + 2,
                (short)(sample * rightGain / FullGain));
        }
    }

    private static double ReadPan()
    {
        string value = Environment.GetEnvironmentVariable(
            PanEnvironmentVariable);
        if (String.IsNullOrEmpty(value))
        {
            return 0.0;
        }

        double pan;
        if (!Double.TryParse(value, NumberStyles.Float,
            CultureInfo.InvariantCulture, out pan) || Double.IsNaN(pan) ||
            Double.IsInfinity(pan) || pan < -1.0 || pan > 1.0)
        {
            throw new InvalidOperationException(
                PanEnvironmentVariable +
                " must be a number between -1.0 and 1.0");
        }
        return pan;
    }

    private static void SetPanGains(double pan, out int left, out int right)
    {
        if (pan < 0.0)
        {
            left = FullGain;
            right = (int)Math.Round((1.0 + pan) * FullGain);
        }
        else
        {
            left = (int)Math.Round((1.0 - pan) * FullGain);
            right = FullGain;
        }
    }

    private static void Check(int result, string operation)
    {
        if (result != 0)
        {
            throw new InvalidOperationException(
                operation + " failed with Windows multimedia error " + result);
        }
    }

    public void Dispose()
    {
        if (handle != IntPtr.Zero)
        {
            try
            {
                NativeWaveOut.waveOutReset(handle);
                lock (syncRoot)
                {
                    ReclaimAllBuffers();
                }
            }
            finally
            {
                NativeWaveOut.waveOutClose(handle);
                handle = IntPtr.Zero;
            }
        }
        for (int index = 0; index < buffers.Length; ++index)
        {
            BufferSlot slot = buffers[index];
            if (slot == null)
            {
                continue;
            }
            if (slot.Header != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(slot.Header);
                slot.Header = IntPtr.Zero;
            }
            if (slot.Data != IntPtr.Zero)
            {
                Marshal.FreeHGlobal(slot.Data);
                slot.Data = IntPtr.Zero;
            }
        }
        bufferChanged.Dispose();
    }
}

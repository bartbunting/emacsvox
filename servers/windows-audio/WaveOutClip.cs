// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

internal static class NativeClipWaveOut
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
    internal static extern int waveOutClose(IntPtr handle);
}

internal sealed class WaveOutClip
{
    private readonly byte[] wave;
    private readonly object playbackLock = new object();
    private NativeClipWaveOut.WaveFormat format;
    private int dataOffset;
    private int dataLength;
    private IntPtr handle = IntPtr.Zero;
    private bool cancelled;

    internal WaveOutClip(byte[] wave)
    {
        this.wave = wave;
        ParseWave();
    }

    internal void Cancel()
    {
        lock (playbackLock)
        {
            cancelled = true;
            if (handle != IntPtr.Zero)
            {
                NativeClipWaveOut.waveOutReset(handle);
            }
        }
    }

    private void ParseWave()
    {
        bool foundFormat = false;
        bool foundData = false;
        using (MemoryStream stream = new MemoryStream(wave, false))
        using (BinaryReader reader = new BinaryReader(stream))
        {
            if (ReadId(reader) != "RIFF" || reader.ReadUInt32() > wave.Length ||
                ReadId(reader) != "WAVE")
            {
                throw new InvalidDataException("Unsupported WAV file");
            }

            while (stream.Position + 8 <= stream.Length)
            {
                string id = ReadId(reader);
                uint chunkLength = reader.ReadUInt32();
                long chunkStart = stream.Position;
                long next = chunkStart + chunkLength + (chunkLength & 1);
                if (next > stream.Length)
                {
                    throw new InvalidDataException("Truncated WAV file");
                }

                if (id == "fmt ")
                {
                    if (chunkLength < 16)
                    {
                        throw new InvalidDataException("Invalid WAV format");
                    }
                    format.FormatTag = reader.ReadUInt16();
                    format.Channels = reader.ReadUInt16();
                    format.SamplesPerSecond = reader.ReadUInt32();
                    format.AverageBytesPerSecond = reader.ReadUInt32();
                    format.BlockAlign = reader.ReadUInt16();
                    format.BitsPerSample = reader.ReadUInt16();
                    format.ExtraSize = 0;
                    foundFormat = true;
                }
                else if (id == "data")
                {
                    dataOffset = checked((int)chunkStart);
                    dataLength = checked((int)chunkLength);
                    foundData = true;
                }
                stream.Position = next;
            }
        }

        if (!foundFormat || !foundData || format.FormatTag != 1 ||
            dataLength == 0)
        {
            throw new InvalidDataException("WAV must contain PCM audio");
        }
    }

    private static string ReadId(BinaryReader reader)
    {
        byte[] id = reader.ReadBytes(4);
        if (id.Length != 4)
        {
            throw new EndOfStreamException();
        }
        return Encoding.ASCII.GetString(id);
    }

    internal void Play()
    {
        IntPtr data = IntPtr.Zero;
        IntPtr header = IntPtr.Zero;
        bool prepared = false;
        bool submitted = false;
        uint headerSize =
            (uint)Marshal.SizeOf(typeof(NativeClipWaveOut.WaveHeader));

        using (AutoResetEvent completed = new AutoResetEvent(false))
        {
            try
            {
                lock (playbackLock)
                {
                    if (cancelled)
                    {
                        return;
                    }
                    Check(NativeClipWaveOut.waveOutOpen(out handle,
                        NativeClipWaveOut.WaveMapper, ref format,
                        completed.SafeWaitHandle.DangerousGetHandle(),
                        IntPtr.Zero, NativeClipWaveOut.CallbackEvent),
                        "waveOutOpen");
                }

                data = Marshal.AllocHGlobal(dataLength);
                Marshal.Copy(wave, dataOffset, data, dataLength);
                NativeClipWaveOut.WaveHeader value =
                    new NativeClipWaveOut.WaveHeader();
                value.Data = data;
                value.BufferLength = (uint)dataLength;
                header = Marshal.AllocHGlobal((int)headerSize);
                Marshal.StructureToPtr(value, header, false);

                Check(NativeClipWaveOut.waveOutPrepareHeader(handle, header,
                    headerSize), "waveOutPrepareHeader");
                prepared = true;
                lock (playbackLock)
                {
                    if (!cancelled)
                    {
                        Check(NativeClipWaveOut.waveOutWrite(handle, header,
                            headerSize), "waveOutWrite");
                        submitted = true;
                    }
                }

                while (submitted)
                {
                    completed.WaitOne();
                    value = (NativeClipWaveOut.WaveHeader)
                        Marshal.PtrToStructure(header,
                            typeof(NativeClipWaveOut.WaveHeader));
                    if ((value.Flags & NativeClipWaveOut.HeaderDone) != 0)
                    {
                        break;
                    }
                }
            }
            catch (Exception error)
            {
                Console.Error.WriteLine(error.Message);
            }
            finally
            {
                IntPtr playbackHandle;
                lock (playbackLock)
                {
                    playbackHandle = handle;
                    handle = IntPtr.Zero;
                }
                if (prepared)
                {
                    NativeClipWaveOut.waveOutUnprepareHeader(
                        playbackHandle, header, headerSize);
                }
                if (playbackHandle != IntPtr.Zero)
                {
                    NativeClipWaveOut.waveOutClose(playbackHandle);
                }
                if (header != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(header);
                }
                if (data != IntPtr.Zero)
                {
                    Marshal.FreeHGlobal(data);
                }
            }
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
}

internal sealed class WaveOutQueue : IDisposable
{
    private sealed class Entry
    {
        internal readonly WaveOutClip Clip;
        internal readonly int Generation;

        internal Entry(WaveOutClip clip, int generation)
        {
            Clip = clip;
            Generation = generation;
        }
    }

    private readonly object queueLock = new object();
    private readonly Queue<Entry> pending = new Queue<Entry>();
    private readonly AutoResetEvent available = new AutoResetEvent(false);
    private readonly Thread worker;
    private WaveOutClip current;
    private int generation;
    private bool disposed;

    internal WaveOutQueue()
    {
        worker = new Thread(Run);
        worker.IsBackground = true;
        worker.Name = "Emacsvox auditory icon queue";
        worker.Start();
    }

    internal void Enqueue(byte[] wave)
    {
        WaveOutClip clip = new WaveOutClip(wave);
        lock (queueLock)
        {
            if (disposed)
            {
                throw new ObjectDisposedException("WaveOutQueue");
            }
            pending.Enqueue(new Entry(clip, generation));
        }
        available.Set();
    }

    internal void Cancel()
    {
        WaveOutClip clip;
        lock (queueLock)
        {
            generation++;
            pending.Clear();
            clip = current;
        }
        if (clip != null)
        {
            clip.Cancel();
        }
        available.Set();
    }

    public void Dispose()
    {
        WaveOutClip clip;
        lock (queueLock)
        {
            if (disposed)
            {
                return;
            }
            disposed = true;
            generation++;
            pending.Clear();
            clip = current;
        }
        if (clip != null)
        {
            clip.Cancel();
        }
        available.Set();
        worker.Join();
        available.Close();
    }

    private void Run()
    {
        while (true)
        {
            Entry entry = null;
            lock (queueLock)
            {
                if (pending.Count > 0)
                {
                    entry = pending.Dequeue();
                }
                else if (disposed)
                {
                    return;
                }
            }
            if (entry == null)
            {
                available.WaitOne();
                continue;
            }

            lock (queueLock)
            {
                if (disposed)
                {
                    return;
                }
                if (entry.Generation != generation)
                {
                    continue;
                }
                current = entry.Clip;
            }
            entry.Clip.Play();
            lock (queueLock)
            {
                if (Object.ReferenceEquals(current, entry.Clip))
                {
                    current = null;
                }
            }
        }
    }
}

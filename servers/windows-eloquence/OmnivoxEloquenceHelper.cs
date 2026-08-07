// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Collections.Generic;

internal sealed class OmnivoxEloquenceAdapter : IOmnivoxCaptureEngine
{
    private static readonly OmnivoxHelperVoice[] EngineVoices =
        new OmnivoxHelperVoice[]
        {
            new OmnivoxHelperVoice("v1", "Adult male 1", "en-US", "male"),
            new OmnivoxHelperVoice("v2", "Adult female 1", "en-US", "female"),
            new OmnivoxHelperVoice("v3", "Child 1", "en-US", null),
            new OmnivoxHelperVoice("v4", "Adult male 2", "en-US", "male"),
            new OmnivoxHelperVoice("v5", "Adult male 3", "en-US", "male"),
            new OmnivoxHelperVoice("v6", "Elderly female 2", "en-US", "female"),
            new OmnivoxHelperVoice("v7", "Elderly female 1", "en-US", "female"),
            new OmnivoxHelperVoice("v8", "Adult male 1 variant", "en-US", "male")
        };

    private static readonly OmnivoxHelperCapabilities EngineCapabilities =
        new OmnivoxHelperCapabilities
        {
            Rate = true,
            AveragePitch = true,
            Volume = true,
            WordMarkers = true,
            SentenceMarkers = true,
            RequestedAnchors = "exact"
        };

    private static readonly Dictionary<string, int> VoicePitchBaselines =
        new Dictionary<string, int>(StringComparer.Ordinal)
        {
            { "v1", 65 },
            { "v2", 81 },
            { "v3", 93 },
            { "v4", 56 },
            { "v5", 69 },
            { "v6", 89 },
            { "v7", 68 },
            { "v8", 61 }
        };

    private readonly OmnivoxEloquenceCapture capture;

    internal OmnivoxEloquenceAdapter(string dllPath)
    {
        capture = new OmnivoxEloquenceCapture(dllPath);
    }

    public string EngineId { get { return "eloquence"; } }
    public string DisplayName { get { return "Eloquence"; } }
    public string Version { get { return capture.Version; } }
    public string HelperName { get { return "Omnivox Eloquence x86 helper"; } }
    public string DefaultVoiceId { get { return "v1"; } }
    public int SampleRate
    {
        get { return OmnivoxEloquenceCapture.SpeechSampleRate; }
    }
    public int Channels { get { return 1; } }
    public OmnivoxHelperVoice[] Voices { get { return EngineVoices; } }
    public OmnivoxHelperCapabilities Capabilities
    {
        get { return EngineCapabilities; }
    }

    public OmnivoxCaptureResult Synthesize(string text, string voiceId,
        double rate, double pitch, double volume,
        OmnivoxHelperAnchor[] anchors)
    {
        // Existing Emacsvox Eloquence operation treats 75 as its normal
        // speed. Preserve that midpoint while providing a bounded range.
        int nativeRate = (int)Math.Round(20.0 + rate * 110.0,
            MidpointRounding.AwayFromZero);
        int nativePitch = (int)Math.Round(
            VoicePitchBaselines[voiceId] * pitch,
            MidpointRounding.AwayFromZero);
        nativePitch = Math.Max(0, Math.Min(100, nativePitch));
        int nativeVolume = (int)Math.Round(volume * 100.0,
            MidpointRounding.AwayFromZero);
        return capture.Synthesize(text, voiceId, nativeRate, nativePitch,
            nativeVolume, anchors);
    }

    public void Stop()
    {
        capture.Stop();
    }

    public void Dispose()
    {
        capture.Dispose();
    }
}

internal static class OmnivoxEloquenceHelper
{
    private const string DefaultDll =
        @"C:\Program Files (x86)\Freedom Scientific\Shared\Eloquence\6.1\ECI.DLL";

    internal static int Main(string[] args)
    {
        string dllPath = args.Length > 0 ? args[0] :
            Environment.GetEnvironmentVariable("OMNIVOX_ECI_DLL");
        if (String.IsNullOrEmpty(dllPath))
        {
            dllPath = Environment.GetEnvironmentVariable("EMACSVOX_ECI_DLL");
        }
        if (String.IsNullOrEmpty(dllPath))
        {
            dllPath = DefaultDll;
        }

        try
        {
            using (OmnivoxEloquenceAdapter engine =
                new OmnivoxEloquenceAdapter(dllPath))
            {
                return new OmnivoxHelperHost(engine).Run();
            }
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("Omnivox Eloquence helper failed: " +
                error.ToString());
            Console.Error.Flush();
            return 1;
        }
    }
}

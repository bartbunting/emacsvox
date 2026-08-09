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
            PitchRange = true,
            Stress = true,
            Richness = true,
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

    private static readonly int[] PitchRange =
        { 0, 5, 15, 20, 25, 30, 47, 64, 81, 100 };
    private static readonly int[] Roughness =
        { 0, 10, 20, 30, 40, 50, 60, 70, 80, 90 };
    private static readonly int[] Breathiness =
        { 0, 4, 8, 12, 16, 20, 24, 28, 32, 36 };
    private static readonly int[] RichnessVolume =
        { 60, 78, 80, 84, 88, 92, 93, 95, 97, 100 };

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
        double rate, double pitch, double? pitchRange, double? stress,
        double? richness, double volume,
        OmnivoxHelperAnchor[] anchors)
    {
        // Existing Emacsvox Eloquence operation treats 75 as its normal
        // speed. Protocol v4's 2.0 maximum maps to 240, within ECI's native
        // 0-through-250 speed range.
        int nativeRate = (int)Math.Round(20.0 + rate * 110.0,
            MidpointRounding.AwayFromZero);
        int nativePitch = (int)Math.Round(
            VoicePitchBaselines[voiceId] * pitch,
            MidpointRounding.AwayFromZero);
        nativePitch = Math.Max(0, Math.Min(100, nativePitch));
        string voiceParameters = MapExtendedAcss(pitchRange, stress, richness);
        int nativeVolume = MapVolume(volume, richness);
        return capture.Synthesize(text, voiceId, nativeRate, nativePitch,
            voiceParameters, nativeVolume, anchors);
    }

    internal static string MapExtendedAcss(double? pitchRange,
        double? stress, double? richness)
    {
        string parameters = "";
        if (pitchRange.HasValue)
        {
            parameters += " `vf" + MapNormalized(pitchRange.Value, PitchRange);
        }
        if (stress.HasValue)
        {
            parameters += " `vr" + MapNormalized(stress.Value, Roughness);
        }
        if (richness.HasValue)
        {
            parameters += " `vy" + MapNormalized(richness.Value, Breathiness);
        }
        return parameters;
    }

    internal static int MapVolume(double volume, double? richness)
    {
        // The legacy richness table compensates for breathier voices with a
        // paired volume. Combine that compensation with independent volume.
        int compensation = richness.HasValue ?
            MapNormalized(richness.Value, RichnessVolume) : 100;
        double mapped = Math.Max(0.0, Math.Min(1.0, volume)) * compensation;
        return (int)Math.Round(mapped, MidpointRounding.AwayFromZero);
    }

    private static int MapNormalized(double value, int[] levels)
    {
        double position = Math.Max(0.0, Math.Min(1.0, value)) *
            (levels.Length - 1);
        int lower = (int)Math.Floor(position);
        int upper = Math.Min(lower + 1, levels.Length - 1);
        double mapped = levels[lower] +
            (levels[upper] - levels[lower]) * (position - lower);
        return (int)Math.Round(mapped, MidpointRounding.AwayFromZero);
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

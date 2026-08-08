// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Collections.Generic;
using System.IO;

internal sealed class OmnivoxDectalkAdapter : IOmnivoxCaptureEngine
{
    private static readonly OmnivoxHelperVoice[] EngineVoices =
        new OmnivoxHelperVoice[]
        {
            new OmnivoxHelperVoice("paul", "Perfect Paul", "en-US", "male"),
            new OmnivoxHelperVoice("betty", "Beautiful Betty", "en-US", "female"),
            new OmnivoxHelperVoice("harry", "Huge Harry", "en-US", "male"),
            new OmnivoxHelperVoice("frank", "Frail Frank", "en-US", "male"),
            new OmnivoxHelperVoice("kit", "Kit the Kid", "en-US", null),
            new OmnivoxHelperVoice("rita", "Rough Rita", "en-US", "female"),
            new OmnivoxHelperVoice("ursula", "Uppity Ursula", "en-US", "female"),
            new OmnivoxHelperVoice("dennis", "Doctor Dennis", "en-US", "male"),
            new OmnivoxHelperVoice("wendy", "Whispering Wendy", "en-US", "female")
        };

    private static readonly Dictionary<string, string> VoiceCodes =
        new Dictionary<string, string>(StringComparer.Ordinal)
        {
            { "paul", ":np" },
            { "betty", ":nb" },
            { "harry", ":nh" },
            { "frank", ":nf" },
            { "kit", ":nk" },
            { "rita", ":nr" },
            { "ursula", ":nu" },
            { "dennis", ":nd" },
            { "wendy", ":nw" }
        };

    private static readonly Dictionary<string, int> VoiceAveragePitch =
        new Dictionary<string, int>(StringComparer.Ordinal)
        {
            { "paul", 122 },
            { "betty", 208 },
            { "harry", 89 },
            { "frank", 155 },
            { "kit", 306 },
            { "rita", 106 },
            { "ursula", 240 },
            { "dennis", 110 },
            { "wendy", 200 }
        };

    private static readonly OmnivoxHelperCapabilities EngineCapabilities =
        new OmnivoxHelperCapabilities
        {
            Rate = true,
            AveragePitch = true,
            Volume = true,
            WordMarkers = true,
            SentenceMarkers = true,
            PhonemeMarkers = true,
            NativeIndexMarkers = true,
            RequestedAnchors = "word_boundary"
        };

    private readonly OmnivoxDectalkCapture capture;

    internal OmnivoxDectalkAdapter(string dllPath)
    {
        capture = new OmnivoxDectalkCapture(dllPath);
    }

    public string EngineId { get { return "dectalk"; } }
    public string DisplayName { get { return "DECtalk Software"; } }
    public string Version { get { return capture.Version; } }
    public string HelperName { get { return "Omnivox DECtalk x86 helper"; } }
    public string DefaultVoiceId { get { return "paul"; } }
    public int SampleRate
    {
        get { return OmnivoxDectalkCapture.SpeechSampleRate; }
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
        string voiceCode;
        if (!VoiceCodes.TryGetValue(voiceId, out voiceCode))
        {
            throw new ArgumentException("Unknown DECtalk voice", "voiceId");
        }

        // Preserve DECtalk's established 225 WPM midpoint while covering its
        // supported 75-through-600 range.
        double mapped = rate <= 0.5 ? 75.0 + rate * 300.0 :
            225.0 + (rate - 0.5) * 750.0;
        int nativeRate = (int)Math.Round(mapped,
            MidpointRounding.AwayFromZero);
        int nativePitch = (int)Math.Round(
            VoiceAveragePitch[voiceId] * pitch,
            MidpointRounding.AwayFromZero);
        nativePitch = Math.Max(50, Math.Min(500, nativePitch));
        return capture.Synthesize(text, voiceCode, nativeRate, nativePitch,
            volume);
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

internal static class OmnivoxDectalkHelper
{
    internal static int Main(string[] args)
    {
        string dllPath = args.Length > 0 ? args[0] :
            Environment.GetEnvironmentVariable("OMNIVOX_DECTALK_DLL");
        if (String.IsNullOrEmpty(dllPath))
        {
            dllPath = Environment.GetEnvironmentVariable(
                "EMACSVOX_DECTALK_DLL");
        }
        if (String.IsNullOrEmpty(dllPath))
        {
            string adjacent = Path.Combine(
                AppDomain.CurrentDomain.BaseDirectory, "DECtalk.dll");
            dllPath = File.Exists(adjacent) ? adjacent :
                Path.GetFullPath(Path.Combine(
                    AppDomain.CurrentDomain.BaseDirectory, "..", "runtime",
                    "DECtalk.dll"));
        }

        try
        {
            using (OmnivoxDectalkAdapter engine =
                new OmnivoxDectalkAdapter(dllPath))
            {
                return new OmnivoxHelperHost(engine).Run();
            }
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("Omnivox DECtalk helper failed: " +
                error.ToString());
            Console.Error.Flush();
            return 1;
        }
    }
}

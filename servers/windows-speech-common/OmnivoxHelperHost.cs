// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

internal static class OmnivoxHelperLog
{
    private static readonly object OutputLock = new object();

    internal static void Event(string name, string details)
    {
        lock (OutputLock)
        {
            Console.Error.WriteLine(
                "{0:O} helper_event={1} pid={2} thread={3}{4}",
                DateTime.UtcNow, name, Process.GetCurrentProcess().Id,
                Thread.CurrentThread.ManagedThreadId,
                String.IsNullOrEmpty(details) ? "" : " " + details);
            Console.Error.Flush();
        }
    }

    internal static string ExceptionDetails(Exception error)
    {
        return error.ToString().Replace('\r', ' ').Replace('\n', ' ');
    }
}

internal sealed class OmnivoxHelperVoice
{
    internal string Id;
    internal string Name;
    internal string Language;
    internal string Gender;

    internal OmnivoxHelperVoice(string id, string name, string language,
        string gender)
    {
        Id = id;
        Name = name;
        Language = language;
        Gender = gender;
    }
}

internal sealed class OmnivoxHelperCapabilities
{
    internal bool Rate { get; set; }
    internal bool AveragePitch { get; set; }
    internal bool PitchRange { get; set; }
    internal bool Stress { get; set; }
    internal bool Richness { get; set; }
    internal bool Volume { get; set; }
    internal bool WordMarkers { get; set; }
    internal bool SentenceMarkers { get; set; }
    internal bool PhonemeMarkers { get; set; }
    internal bool NativeIndexMarkers { get; set; }
    internal string RequestedAnchors { get; set; }
    internal bool LanguageSwitching { get; set; }
}

internal sealed class OmnivoxHelperAnchor
{
    internal string Id;
    internal uint TextOffset;
    internal string Affinity;

    internal OmnivoxHelperAnchor(string id, uint textOffset, string affinity)
    {
        Id = id;
        TextOffset = textOffset;
        Affinity = affinity;
    }
}

internal sealed class OmnivoxHelperMarker
{
    internal string Kind;
    internal ulong FrameOffset;
    internal uint? TextStart;
    internal uint? TextLength;
    internal string Value;

    internal OmnivoxHelperMarker(string kind, ulong frameOffset,
        uint? textStart, uint? textLength, string value)
    {
        Kind = kind;
        FrameOffset = frameOffset;
        TextStart = textStart;
        TextLength = textLength;
        Value = value;
    }
}

internal sealed class OmnivoxTextSpan
{
    internal int Start;
    internal int Length;

    internal OmnivoxTextSpan(int start, int length)
    {
        Start = start;
        Length = length;
    }
}

/// <summary>
/// Conservative source-text boundaries shared by capture adapters whose
/// native APIs can time inserted indexes but do not report sentence ranges.
/// </summary>
internal static class OmnivoxTextBoundaries
{
    internal static OmnivoxTextSpan[] Sentences(string text)
    {
        List<OmnivoxTextSpan> spans = new List<OmnivoxTextSpan>();
        int position = 0;
        while (position < text.Length)
        {
            while (position < text.Length && Char.IsWhiteSpace(text, position))
            {
                ++position;
            }
            if (position >= text.Length)
            {
                break;
            }

            int start = position;
            bool completed = false;
            while (position < text.Length)
            {
                char value = text[position];
                if (value == '\r' || value == '\n')
                {
                    AddNonempty(spans, start, position);
                    completed = true;
                    break;
                }
                ++position;
                if (!IsSentenceTerminator(value))
                {
                    continue;
                }
                while (position < text.Length &&
                    IsSentenceCloser(text[position]))
                {
                    ++position;
                }
                if (position == text.Length ||
                    Char.IsWhiteSpace(text, position))
                {
                    AddNonempty(spans, start, position);
                    completed = true;
                    break;
                }
            }
            if (!completed)
            {
                AddNonempty(spans, start, text.Length);
                position = text.Length;
            }
        }
        return spans.ToArray();
    }

    private static void AddNonempty(List<OmnivoxTextSpan> spans,
        int start, int end)
    {
        if (end > start)
        {
            spans.Add(new OmnivoxTextSpan(start, end - start));
        }
    }

    private static bool IsSentenceTerminator(char value)
    {
        return value == '.' || value == '!' || value == '?' ||
            value == '\u2026' || value == '\u3002' ||
            value == '\uff01' || value == '\uff1f';
    }

    private static bool IsSentenceCloser(char value)
    {
        return value == '\'' || value == '"' || value == '\u2019' ||
            value == '\u201d' || value == ')' || value == ']' ||
            value == '}';
    }
}

internal sealed class OmnivoxCaptureResult
{
    internal byte[] Audio;
    internal OmnivoxHelperMarker[] Markers;

    internal OmnivoxCaptureResult(byte[] audio,
        OmnivoxHelperMarker[] markers)
    {
        Audio = audio;
        Markers = markers;
    }
}

internal interface IOmnivoxCaptureEngine : IDisposable
{
    string EngineId { get; }
    string DisplayName { get; }
    string Version { get; }
    string HelperName { get; }
    string DefaultVoiceId { get; }
    int SampleRate { get; }
    int Channels { get; }
    OmnivoxHelperVoice[] Voices { get; }
    OmnivoxHelperCapabilities Capabilities { get; }
    OmnivoxCaptureResult Synthesize(string text, string voiceId, double rate,
        double pitch, double? pitchRange, double? stress, double? richness,
        double volume, OmnivoxHelperAnchor[] anchors);
    void Stop();
}

/// <summary>
/// Engine-neutral implementation of Omnivox helper protocol versions 1-3.
/// Native adapters provide inventory, captured PCM, and interruption only.
/// </summary>
internal sealed class OmnivoxHelperHost
{
    private const int LatestProtocolVersion = 3;
    private const int AnchorProtocolVersion = 2;
    private const int LegacyProtocolVersion = 1;
    private const int MaximumFrameBytes = 1024 * 1024;
    private const int MaximumTextBytes = 256 * 1024;
    private const int MaximumAudioChunkBytes = 256 * 1024;
    private const int MaximumAudioBytes = 128 * 1024 * 1024;
    private const int MaximumMarkers = 4096;
    private const int MaximumStringLength = 16 * 1024;
    private const int MaximumAnchorIdBytes = 128;

    private sealed class ProtocolException : Exception
    {
        internal readonly string Code;
        internal readonly bool Retryable;

        internal ProtocolException(string code, string message,
            bool retryable)
            : base(message)
        {
            Code = code;
            Retryable = retryable;
        }
    }

    private sealed class ActiveSynthesis
    {
        internal ulong RequestId;
        internal string Text;
        internal string VoiceId;
        internal double Rate;
        internal double Pitch;
        internal double? PitchRange;
        internal double? Stress;
        internal double? Richness;
        internal double Volume;
        internal OmnivoxHelperAnchor[] Anchors;
        internal volatile bool Cancelled;
        internal Thread Worker;
    }

    private readonly IOmnivoxCaptureEngine engine;
    private readonly StreamReader input;
    private readonly StreamWriter output;
    private readonly JavaScriptSerializer json;
    private readonly object outputLock = new object();
    private readonly object stateLock = new object();
    private ActiveSynthesis active;
    private bool negotiated;
    private int selectedProtocolVersion;
    private bool shuttingDown;

    internal OmnivoxHelperHost(IOmnivoxCaptureEngine engine)
    {
        if (engine == null)
        {
            throw new ArgumentNullException("engine");
        }
        this.engine = engine;
        if (String.IsNullOrEmpty(engine.EngineId) ||
            String.IsNullOrEmpty(engine.DisplayName) ||
            String.IsNullOrEmpty(engine.Version) ||
            String.IsNullOrEmpty(engine.HelperName) ||
            String.IsNullOrEmpty(engine.DefaultVoiceId) ||
            engine.SampleRate <= 0 || engine.Channels <= 0 ||
            engine.Voices == null || engine.Voices.Length == 0 ||
            engine.Capabilities == null)
        {
            throw new ArgumentException("capture engine metadata is incomplete",
                "engine");
        }
        if (!HasVoice(engine.DefaultVoiceId))
        {
            throw new ArgumentException(
                "capture engine default voice is not in inventory", "engine");
        }

        input = new StreamReader(Console.OpenStandardInput(),
            new UTF8Encoding(false, true), false, 4096);
        output = new StreamWriter(Console.OpenStandardOutput(),
            new UTF8Encoding(false), 4096);
        output.AutoFlush = true;
        json = new JavaScriptSerializer();
        json.MaxJsonLength = MaximumFrameBytes;
        json.RecursionLimit = 32;
        OmnivoxHelperLog.Event("process_started",
            "engine=" + engine.EngineId + " engine_version=" +
            engine.Version + " helper=\"" + engine.HelperName + "\"");
    }

    internal int Run()
    {
        OmnivoxHelperLog.Event("protocol_loop_started", "");
        while (!shuttingDown)
        {
            string line;
            try
            {
                line = ReadBoundedLine();
            }
            catch (ProtocolException error)
            {
                WriteError(null, error.Code, error.Message, error.Retryable);
                continue;
            }
            if (line == null)
            {
                break;
            }
            Dispatch(line);
        }

        StopAndJoinActive();
        OmnivoxHelperLog.Event("protocol_loop_stopped", "");
        return 0;
    }

    private string ReadBoundedLine()
    {
        StringBuilder line = new StringBuilder();
        int encodedBytes = 0;
        bool oversized = false;
        while (true)
        {
            int value = input.Read();
            if (value < 0)
            {
                if (line.Length == 0 && !oversized)
                {
                    return null;
                }
                throw Fault("invalid_request",
                    "helper frame ended before its newline terminator", false);
            }
            char character = (char)value;
            if (character == '\n')
            {
                break;
            }
            encodedBytes += character <= 0x7f ? 1 :
                (character <= 0x7ff ? 2 : 3);
            if (encodedBytes > MaximumFrameBytes)
            {
                oversized = true;
            }
            if (!oversized)
            {
                line.Append(character);
            }
        }

        if (oversized)
        {
            throw Fault("payload_too_large",
                "helper frame exceeds the 1 MiB limit", false);
        }
        if (line.Length > 0 && line[line.Length - 1] == '\r')
        {
            line.Length -= 1;
        }
        return line.ToString();
    }

    private void Dispatch(string line)
    {
        ulong? requestId = null;
        try
        {
            IDictionary<string, object> request = json.DeserializeObject(line)
                as IDictionary<string, object>;
            if (request == null)
            {
                throw Fault("invalid_request",
                    "helper request must be a JSON object", false);
            }

            requestId = ReadUnsigned(request, "request_id");
            int version = ReadInteger(request, "protocol_version");
            if (version < LegacyProtocolVersion ||
                version > LatestProtocolVersion)
            {
                throw Fault("unsupported_version",
                    "unsupported helper protocol version " + version, false);
            }
            string type = ReadString(request, "type", false);
            if (!negotiated && type != "hello")
            {
                throw Fault("invalid_request",
                    "hello must be the first helper request", false);
            }
            if (negotiated && version != selectedProtocolVersion)
            {
                throw Fault("unsupported_version",
                    "request does not use the negotiated helper protocol", false);
            }

            switch (type)
            {
                case "hello":
                    HandleHello(requestId.Value, version, request);
                    break;
                case "describe":
                    RequireFields(request, "protocol_version", "request_id",
                        "type");
                    WriteDescriptor(requestId.Value);
                    break;
                case "ping":
                    RequireFields(request, "protocol_version", "request_id",
                        "type");
                    WriteSimple(requestId.Value, "pong");
                    break;
                case "synthesize":
                    HandleSynthesize(requestId.Value, request);
                    break;
                case "cancel":
                    HandleCancel(requestId.Value, request);
                    break;
                case "shutdown":
                    RequireFields(request, "protocol_version", "request_id",
                        "type");
                    WriteSimple(requestId.Value, "shutting_down");
                    shuttingDown = true;
                    break;
                default:
                    throw Fault("invalid_request",
                        "unknown helper request type: " + type, false);
            }
        }
        catch (ProtocolException error)
        {
            WriteError(requestId, error.Code, error.Message, error.Retryable);
        }
        catch (Exception error)
        {
            WriteError(requestId, "invalid_request",
                "invalid helper request: " + error.Message, false);
        }
    }

    private void HandleHello(ulong requestId, int requestVersion,
        IDictionary<string, object> request)
    {
        RequireFields(request, "protocol_version", "request_id", "type",
            "supported_protocol_versions");
        if (negotiated)
        {
            throw Fault("invalid_request",
                "helper protocol is already negotiated", false);
        }
        object value = Required(request, "supported_protocol_versions");
        IEnumerable versions = value as IEnumerable;
        if (versions == null || value is string)
        {
            throw Fault("invalid_request",
                "supported_protocol_versions must be an array", false);
        }
        int count = 0;
        int highestSupported = 0;
        HashSet<int> seen = new HashSet<int>();
        foreach (object item in versions)
        {
            int version = ConvertInteger(item,
                "supported_protocol_versions");
            ++count;
            if (count > 16 || version <= 0 || !seen.Add(version))
            {
                throw Fault("invalid_request",
                    "supported_protocol_versions is invalid", false);
            }
            if (version >= LegacyProtocolVersion &&
                version <= LatestProtocolVersion)
            {
                highestSupported = Math.Max(highestSupported, version);
            }
        }
        if (count == 0 ||
            highestSupported == 0 ||
            !seen.Contains(requestVersion))
        {
            throw Fault("unsupported_version",
                "no supported helper protocol version was offered", false);
        }

        selectedProtocolVersion = highestSupported;
        negotiated = true;
        Dictionary<string, object> response = Response(requestId, "hello");
        response["selected_protocol_version"] = selectedProtocolVersion;
        response["helper_name"] = engine.HelperName;
        response["helper_version"] = "0.1.0";
        WriteFrame(response);
    }

    private void HandleSynthesize(ulong requestId,
        IDictionary<string, object> request)
    {
        if (selectedProtocolVersion >= AnchorProtocolVersion)
        {
            RequireFields(request, "protocol_version", "request_id", "type",
                "text", "settings", "anchors");
        }
        else
        {
            RequireFields(request, "protocol_version", "request_id", "type",
                "text", "settings");
        }
        string text = ReadText(request);
        if (Encoding.UTF8.GetByteCount(text) > MaximumTextBytes)
        {
            throw Fault("payload_too_large",
                "synthesis text exceeds the 256 KiB limit", false);
        }
        if (text.IndexOf('\0') >= 0)
        {
            throw Fault("invalid_parameter",
                "native speech text cannot contain a NUL character", false);
        }

        IDictionary<string, object> settings = Required(request, "settings")
            as IDictionary<string, object>;
        if (settings == null)
        {
            throw Fault("invalid_parameter",
                "settings must be a JSON object", false);
        }
        if (selectedProtocolVersion >= LatestProtocolVersion)
        {
            RequireFields(settings, "voice_id", "rate", "pitch", "volume",
                "pitch_range", "stress", "richness");
        }
        else
        {
            RequireFields(settings, "voice_id", "rate", "pitch", "volume");
        }
        string voiceId = settings["voice_id"] == null ?
            engine.DefaultVoiceId : ReadString(settings, "voice_id", false);
        if (!HasVoice(voiceId))
        {
            throw Fault("voice_not_found",
                engine.DisplayName + " voice was not found: " + voiceId,
                false);
        }

        ActiveSynthesis synthesis = new ActiveSynthesis();
        synthesis.RequestId = requestId;
        synthesis.Text = text;
        synthesis.VoiceId = voiceId;
        synthesis.Rate = ReadNumber(settings, "rate", 0.0, 1.0);
        synthesis.Pitch = ReadNumber(settings, "pitch", 0.5, 2.0);
        synthesis.PitchRange = ReadOptionalAcssNumber(settings, "pitch_range",
            engine.Capabilities.PitchRange);
        synthesis.Stress = ReadOptionalAcssNumber(settings, "stress",
            engine.Capabilities.Stress);
        synthesis.Richness = ReadOptionalAcssNumber(settings, "richness",
            engine.Capabilities.Richness);
        synthesis.Volume = ReadNumber(settings, "volume", 0.0, 1.0);
        synthesis.Anchors = selectedProtocolVersion >= AnchorProtocolVersion ?
            ReadAnchors(request, text) : new OmnivoxHelperAnchor[0];
        synthesis.Worker = new Thread(delegate() { SynthesisWorker(synthesis); });
        synthesis.Worker.Name = "omnivox-" + engine.EngineId + "-synthesis";
        synthesis.Worker.IsBackground = true;

        lock (stateLock)
        {
            if (active != null)
            {
                throw Fault("busy",
                    engine.DisplayName + " permits one active synthesis", true);
            }
            active = synthesis;
        }

        OmnivoxHelperLog.Event("request_accepted",
            "request_id=" + requestId.ToString(CultureInfo.InvariantCulture) +
            " voice=" + voiceId + " text_bytes=" +
            Encoding.UTF8.GetByteCount(text).ToString(
                CultureInfo.InvariantCulture) + " anchors=" +
            synthesis.Anchors.Length.ToString(CultureInfo.InvariantCulture));

        Dictionary<string, object> started = Response(requestId,
            "synthesis_started");
        Dictionary<string, object> format = new Dictionary<string, object>();
        format["sample_rate"] = engine.SampleRate;
        format["channels"] = engine.Channels;
        format["sample_format"] = "pcm_s16_le";
        started["format"] = format;
        started["actual_voice_id"] = voiceId;
        WriteFrame(started);
        try
        {
            synthesis.Worker.Start();
        }
        catch
        {
            lock (stateLock)
            {
                if (Object.ReferenceEquals(active, synthesis))
                {
                    active = null;
                }
            }
            throw;
        }
    }

    private void SynthesisWorker(ActiveSynthesis synthesis)
    {
        Stopwatch elapsed = Stopwatch.StartNew();
        string request = "request_id=" + synthesis.RequestId.ToString(
            CultureInfo.InvariantCulture);
        try
        {
            OmnivoxHelperLog.Event("native_synthesis_started", request);
            OmnivoxCaptureResult result = engine.Synthesize(synthesis.Text,
                synthesis.VoiceId, synthesis.Rate, synthesis.Pitch,
                synthesis.PitchRange, synthesis.Stress, synthesis.Richness,
                synthesis.Volume, synthesis.Anchors);
            if (result == null)
            {
                throw new InvalidOperationException(
                    "native engine returned no synthesis result");
            }
            byte[] audio = result.Audio;
            OmnivoxHelperMarker[] markers = result.Markers;
            int frameBytes = checked(engine.Channels * 2);
            if (audio == null || audio.Length > MaximumAudioBytes ||
                audio.Length % frameBytes != 0)
            {
                throw new InvalidOperationException(
                    "native engine returned invalid or oversized PCM");
            }
            ulong frameCount = (ulong)(audio.Length / frameBytes);
            ValidateMarkers(markers, frameCount, synthesis.Text,
                synthesis.Anchors);
            OmnivoxHelperLog.Event("native_synthesis_completed",
                request + " frames=" + frameCount.ToString(
                    CultureInfo.InvariantCulture) + " markers=" +
                markers.Length.ToString(CultureInfo.InvariantCulture) +
                " elapsed_ms=" + elapsed.ElapsedMilliseconds.ToString(
                    CultureInfo.InvariantCulture));
            if (synthesis.Cancelled)
            {
                WriteSimple(synthesis.RequestId, "synthesis_cancelled");
                return;
            }

            int maximumChunk = MaximumAudioChunkBytes -
                (MaximumAudioChunkBytes % frameBytes);
            uint sequence = 0;
            for (int offset = 0; offset < audio.Length; offset += maximumChunk)
            {
                int count = Math.Min(maximumChunk, audio.Length - offset);
                Dictionary<string, object> response = Response(
                    synthesis.RequestId, "audio_chunk");
                Dictionary<string, object> chunk =
                    new Dictionary<string, object>();
                chunk["sequence"] = sequence++;
                chunk["data_base64"] = Convert.ToBase64String(audio,
                    offset, count);
                response["chunk"] = chunk;
                WriteFrame(response);
            }
            if (markers.Length > 0)
            {
                WriteMarkers(synthesis.RequestId, markers);
            }
            Dictionary<string, object> completed = Response(
                synthesis.RequestId, "synthesis_completed");
            completed["frame_count"] = frameCount;
            WriteFrame(completed);
            OmnivoxHelperLog.Event("request_completed",
                request + " elapsed_ms=" + elapsed.ElapsedMilliseconds.ToString(
                    CultureInfo.InvariantCulture));
        }
        catch (Exception error)
        {
            OmnivoxHelperLog.Event("request_failed",
                request + " elapsed_ms=" + elapsed.ElapsedMilliseconds.ToString(
                    CultureInfo.InvariantCulture) + " error=\"" +
                OmnivoxHelperLog.ExceptionDetails(error) + "\"");
            if (synthesis.Cancelled)
            {
                WriteSimple(synthesis.RequestId, "synthesis_cancelled");
            }
            else
            {
                WriteError(synthesis.RequestId, "synthesis_failed",
                    BoundedMessage(error), true);
            }
        }
        finally
        {
            lock (stateLock)
            {
                if (Object.ReferenceEquals(active, synthesis))
                {
                    active = null;
                }
            }
        }
    }

    private static void ValidateMarkers(OmnivoxHelperMarker[] markers,
        ulong frameCount, string text, OmnivoxHelperAnchor[] anchors)
    {
        if (markers == null || markers.Length > MaximumMarkers)
        {
            throw new InvalidOperationException(
                "native engine returned invalid or too many markers");
        }
        ulong textBytes = (ulong)Encoding.UTF8.GetByteCount(text);
        HashSet<string> requestedAnchors = new HashSet<string>(
            StringComparer.Ordinal);
        foreach (OmnivoxHelperAnchor anchor in anchors)
        {
            requestedAnchors.Add(anchor.Id);
        }
        HashSet<string> resolvedAnchors = new HashSet<string>(
            StringComparer.Ordinal);
        foreach (OmnivoxHelperMarker marker in markers)
        {
            if (marker == null || marker.FrameOffset > frameCount ||
                (marker.Kind != "word" && marker.Kind != "sentence" &&
                 marker.Kind != "phoneme" && marker.Kind != "native_index" &&
                 marker.Kind != "requested_anchor") ||
                marker.TextStart.HasValue != marker.TextLength.HasValue ||
                (marker.Value != null &&
                 Encoding.UTF8.GetByteCount(marker.Value) >
                    MaximumStringLength))
            {
                throw new InvalidOperationException(
                    "native engine returned an invalid marker");
            }
            if (marker.Kind == "requested_anchor" &&
                (marker.Value == null ||
                 !requestedAnchors.Contains(marker.Value) ||
                 !resolvedAnchors.Add(marker.Value)))
            {
                throw new InvalidOperationException(
                    "native engine returned an unknown or duplicate anchor");
            }
            if (marker.TextStart.HasValue &&
                (ulong)marker.TextStart.Value + marker.TextLength.Value >
                    textBytes)
            {
                throw new InvalidOperationException(
                    "native engine marker exceeds the synthesis text");
            }
        }
    }

    private void WriteMarkers(ulong requestId,
        OmnivoxHelperMarker[] markers)
    {
        object[] values = new object[markers.Length];
        for (int index = 0; index < markers.Length; ++index)
        {
            OmnivoxHelperMarker marker = markers[index];
            Dictionary<string, object> value =
                new Dictionary<string, object>();
            value["kind"] = marker.Kind;
            value["frame_offset"] = marker.FrameOffset;
            if (marker.TextStart.HasValue)
            {
                value["text_start"] = marker.TextStart.Value;
                value["text_length"] = marker.TextLength.Value;
            }
            if (marker.Value != null)
            {
                value["value"] = marker.Value;
            }
            values[index] = value;
        }
        Dictionary<string, object> response = Response(requestId, "markers");
        response["markers"] = values;
        WriteFrame(response);
    }

    private static OmnivoxHelperAnchor[] ReadAnchors(
        IDictionary<string, object> request, string text)
    {
        object raw = Required(request, "anchors");
        IEnumerable values = raw as IEnumerable;
        if (values == null || raw is string)
        {
            throw Fault("invalid_parameter", "anchors must be an array", false);
        }

        HashSet<uint> boundaries = new HashSet<uint>();
        uint byteOffset = 0;
        boundaries.Add(byteOffset);
        for (int position = 0; position < text.Length;)
        {
            int length = Char.IsHighSurrogate(text[position]) &&
                position + 1 < text.Length &&
                Char.IsLowSurrogate(text[position + 1]) ? 2 : 1;
            byteOffset = checked(byteOffset +
                (uint)Encoding.UTF8.GetByteCount(
                    text.Substring(position, length)));
            boundaries.Add(byteOffset);
            position += length;
        }

        List<OmnivoxHelperAnchor> anchors =
            new List<OmnivoxHelperAnchor>();
        HashSet<string> identifiers = new HashSet<string>(
            StringComparer.Ordinal);
        foreach (object rawAnchor in values)
        {
            IDictionary<string, object> value = rawAnchor as
                IDictionary<string, object>;
            if (value == null)
            {
                throw Fault("invalid_parameter",
                    "each anchor must be an object", false);
            }
            RequireFields(value, "id", "text_offset", "affinity");
            string id = ReadString(value, "id", false);
            uint textOffset = ReadNonnegativeUInt(value, "text_offset");
            string affinity = ReadString(value, "affinity", false);
            if (Encoding.UTF8.GetByteCount(id) > MaximumAnchorIdBytes ||
                !identifiers.Add(id) || !boundaries.Contains(textOffset) ||
                (affinity != "before" && affinity != "after"))
            {
                throw Fault("invalid_parameter",
                    "anchor ID, text offset, or affinity is invalid", false);
            }
            anchors.Add(new OmnivoxHelperAnchor(id, textOffset, affinity));
            if (anchors.Count > MaximumMarkers)
            {
                throw Fault("payload_too_large",
                    "too many requested anchors", false);
            }
        }
        return anchors.ToArray();
    }

    private void HandleCancel(ulong requestId,
        IDictionary<string, object> request)
    {
        RequireFields(request, "protocol_version", "request_id", "type",
            "target_request_id");
        ulong targetRequestId = ReadUnsigned(request, "target_request_id");
        if (targetRequestId == requestId)
        {
            throw Fault("invalid_request",
                "cancel request cannot target itself", false);
        }

        ActiveSynthesis synthesis;
        lock (stateLock)
        {
            synthesis = active;
            if (synthesis == null || synthesis.RequestId != targetRequestId)
            {
                throw Fault("invalid_request",
                    "target synthesis is not active", false);
            }
            synthesis.Cancelled = true;
        }
        engine.Stop();
        OmnivoxHelperLog.Event("cancel_requested",
            "request_id=" + requestId.ToString(CultureInfo.InvariantCulture) +
            " target_request_id=" + targetRequestId.ToString(
                CultureInfo.InvariantCulture));

        Dictionary<string, object> response = Response(requestId,
            "cancel_accepted");
        response["target_request_id"] = targetRequestId;
        WriteFrame(response);
    }

    private void StopAndJoinActive()
    {
        ActiveSynthesis synthesis;
        lock (stateLock)
        {
            synthesis = active;
            if (synthesis != null)
            {
                synthesis.Cancelled = true;
            }
        }
        if (synthesis == null)
        {
            return;
        }
        engine.Stop();
        bool joined = synthesis.Worker.Join(TimeSpan.FromSeconds(10));
        OmnivoxHelperLog.Event("shutdown_join",
            "request_id=" + synthesis.RequestId.ToString(
                CultureInfo.InvariantCulture) + " joined=" +
            (joined ? "true" : "false"));
    }

    private void WriteDescriptor(ulong requestId)
    {
        Dictionary<string, object> descriptor =
            new Dictionary<string, object>();
        descriptor["id"] = engine.EngineId;
        descriptor["display_name"] = engine.DisplayName;
        descriptor["version"] = engine.Version;
        descriptor["availability"] = Status("available");
        descriptor["health"] = Status("healthy");

        OmnivoxHelperCapabilities advertised = engine.Capabilities;
        Dictionary<string, object> capabilities =
            new Dictionary<string, object>();
        Dictionary<string, object> acss = new Dictionary<string, object>();
        acss["rate"] = advertised.Rate;
        acss["average_pitch"] = advertised.AveragePitch;
        acss["pitch_range"] = advertised.PitchRange;
        acss["stress"] = advertised.Stress;
        acss["richness"] = advertised.Richness;
        acss["volume"] = advertised.Volume;
        capabilities["acss"] = acss;
        capabilities["audio_output"] = "buffered_pcm";
        capabilities["cancellation"] = "synthesis_and_playback";
        Dictionary<string, object> concurrency =
            new Dictionary<string, object>();
        concurrency["mode"] = "serialized";
        capabilities["concurrency"] = concurrency;
        Dictionary<string, object> markers =
            new Dictionary<string, object>();
        markers["word"] = advertised.WordMarkers;
        markers["sentence"] = advertised.SentenceMarkers;
        markers["phoneme"] = advertised.PhonemeMarkers;
        markers["native_index"] = advertised.NativeIndexMarkers;
        if (selectedProtocolVersion >= AnchorProtocolVersion)
        {
            markers["requested_anchors"] =
                !String.IsNullOrEmpty(advertised.RequestedAnchors) ?
                advertised.RequestedAnchors : "none";
        }
        capabilities["markers"] = markers;
        capabilities["language_switching"] = advertised.LanguageSwitching;
        capabilities["native_extensions"] = new object[0];
        descriptor["capabilities"] = capabilities;

        object[] voices = new object[engine.Voices.Length];
        for (int index = 0; index < engine.Voices.Length; ++index)
        {
            OmnivoxHelperVoice voice = engine.Voices[index];
            Dictionary<string, object> item =
                new Dictionary<string, object>();
            Dictionary<string, object> id = new Dictionary<string, object>();
            id["engine_id"] = engine.EngineId;
            id["voice_id"] = voice.Id;
            item["id"] = id;
            item["display_name"] = voice.Name;
            item["language"] = voice.Language;
            item["gender"] = voice.Gender;
            item["quality"] = "compact";
            item["availability"] = Status("available");
            voices[index] = item;
        }
        descriptor["voices"] = voices;
        descriptor["default_voice_id"] = engine.DefaultVoiceId;

        Dictionary<string, object> response = Response(requestId,
            "descriptor");
        response["descriptor"] = descriptor;
        WriteFrame(response);
    }

    private bool HasVoice(string voiceId)
    {
        foreach (OmnivoxHelperVoice voice in engine.Voices)
        {
            if (voice.Id == voiceId)
            {
                return true;
            }
        }
        return false;
    }

    private static Dictionary<string, object> Status(string status)
    {
        Dictionary<string, object> value = new Dictionary<string, object>();
        value["status"] = status;
        return value;
    }

    private Dictionary<string, object> Response(ulong requestId,
        string type)
    {
        Dictionary<string, object> response =
            new Dictionary<string, object>();
        response["protocol_version"] = selectedProtocolVersion == 0 ?
            LatestProtocolVersion : selectedProtocolVersion;
        response["request_id"] = requestId;
        response["type"] = type;
        return response;
    }

    private void WriteSimple(ulong requestId, string type)
    {
        WriteFrame(Response(requestId, type));
    }

    private void WriteError(ulong? requestId, string code, string message,
        bool retryable)
    {
        Dictionary<string, object> response =
            new Dictionary<string, object>();
        response["protocol_version"] = selectedProtocolVersion == 0 ?
            LatestProtocolVersion : selectedProtocolVersion;
        response["request_id"] = requestId.HasValue ?
            (object)requestId.Value : null;
        response["type"] = "error";
        response["code"] = code;
        response["message"] = message;
        response["retryable"] = retryable;
        WriteFrame(response);
    }

    private void WriteFrame(Dictionary<string, object> response)
    {
        string line = json.Serialize(response);
        if (Encoding.UTF8.GetByteCount(line) > MaximumFrameBytes)
        {
            throw new InvalidOperationException(
                "helper response exceeds the 1 MiB frame limit");
        }
        lock (outputLock)
        {
            output.WriteLine(line);
        }
    }

    private static object Required(IDictionary<string, object> values,
        string field)
    {
        object value;
        if (!values.TryGetValue(field, out value))
        {
            throw Fault("invalid_request",
                "missing required field: " + field, false);
        }
        return value;
    }

    private static string ReadString(IDictionary<string, object> values,
        string field, bool allowEmpty)
    {
        string value = Required(values, field) as string;
        if (value == null || (!allowEmpty && value.Length == 0) ||
            Encoding.UTF8.GetByteCount(value) > MaximumStringLength)
        {
            throw Fault("invalid_request", "invalid string field: " + field,
                false);
        }
        return value;
    }

    private static string ReadText(IDictionary<string, object> values)
    {
        string value = Required(values, "text") as string;
        if (value == null)
        {
            throw Fault("invalid_request", "invalid string field: text",
                false);
        }
        return value;
    }

    private static int ReadInteger(IDictionary<string, object> values,
        string field)
    {
        return ConvertInteger(Required(values, field), field);
    }

    private static int ConvertInteger(object value, string field)
    {
        try
        {
            decimal number = Convert.ToDecimal(value,
                CultureInfo.InvariantCulture);
            if (Decimal.Truncate(number) != number || number < Int32.MinValue ||
                number > Int32.MaxValue)
            {
                throw new OverflowException();
            }
            return Decimal.ToInt32(number);
        }
        catch
        {
            throw Fault("invalid_request", "invalid integer field: " + field,
                false);
        }
    }

    private static ulong ReadUnsigned(IDictionary<string, object> values,
        string field)
    {
        object value = Required(values, field);
        try
        {
            decimal number = Convert.ToDecimal(value,
                CultureInfo.InvariantCulture);
            if (Decimal.Truncate(number) != number || number <= 0 ||
                number > UInt64.MaxValue)
            {
                throw new OverflowException();
            }
            return Decimal.ToUInt64(number);
        }
        catch
        {
            throw Fault("invalid_request",
                "invalid positive integer field: " + field, false);
        }
    }

    private static uint ReadNonnegativeUInt(
        IDictionary<string, object> values, string field)
    {
        object value = Required(values, field);
        try
        {
            decimal number = Convert.ToDecimal(value,
                CultureInfo.InvariantCulture);
            if (Decimal.Truncate(number) != number || number < 0 ||
                number > UInt32.MaxValue)
            {
                throw new OverflowException();
            }
            return Decimal.ToUInt32(number);
        }
        catch
        {
            throw Fault("invalid_request",
                "invalid nonnegative integer field: " + field, false);
        }
    }

    private static double ReadNumber(IDictionary<string, object> values,
        string field, double minimum, double maximum)
    {
        try
        {
            double value = Convert.ToDouble(Required(values, field),
                CultureInfo.InvariantCulture);
            if (Double.IsNaN(value) || Double.IsInfinity(value) ||
                value < minimum || value > maximum)
            {
                throw new OverflowException();
            }
            return value;
        }
        catch (ProtocolException)
        {
            throw;
        }
        catch
        {
            throw Fault("invalid_parameter",
                "invalid numeric field: " + field, false);
        }
    }

    private double? ReadOptionalAcssNumber(
        IDictionary<string, object> values, string field, bool supported)
    {
        object raw;
        if (!values.TryGetValue(field, out raw) || raw == null)
        {
            return null;
        }
        if (!supported)
        {
            throw Fault("invalid_parameter",
                engine.DisplayName + " does not support ACSS " + field,
                false);
        }
        return ReadNumber(values, field, 0.0, 1.0);
    }

    private static void RequireFields(IDictionary<string, object> values,
        params string[] allowed)
    {
        HashSet<string> names = new HashSet<string>(allowed,
            StringComparer.Ordinal);
        foreach (string name in values.Keys)
        {
            if (!names.Contains(name))
            {
                throw Fault("invalid_request",
                    "unknown helper request field: " + name, false);
            }
        }
    }

    private static string BoundedMessage(Exception error)
    {
        string message = error.Message;
        if (String.IsNullOrEmpty(message))
        {
            message = error.GetType().Name;
        }
        if (message.Length > MaximumStringLength)
        {
            message = message.Substring(0, MaximumStringLength);
        }
        return message;
    }

    private static ProtocolException Fault(string code, string message,
        bool retryable)
    {
        return new ProtocolException(code, message, retryable);
    }
}

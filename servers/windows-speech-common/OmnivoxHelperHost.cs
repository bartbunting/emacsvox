// Copyright (C) 2026 Bart Bunting
// SPDX-License-Identifier: GPL-2.0-or-later
//
// This file is not part of GNU Emacs, but the same permissions apply.
// See the file COPYING in this distribution.

using System;
using System.Collections;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

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
    internal bool LanguageSwitching { get; set; }
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
        double pitch, double volume);
    void Stop();
}

/// <summary>
/// Engine-neutral implementation of Omnivox helper protocol version 1.
/// Native adapters provide inventory, captured PCM, and interruption only.
/// </summary>
internal sealed class OmnivoxHelperHost
{
    private const int ProtocolVersion = 1;
    private const int MaximumFrameBytes = 1024 * 1024;
    private const int MaximumTextBytes = 256 * 1024;
    private const int MaximumAudioChunkBytes = 256 * 1024;
    private const int MaximumAudioBytes = 128 * 1024 * 1024;
    private const int MaximumMarkers = 4096;
    private const int MaximumStringLength = 16 * 1024;

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
        internal double Volume;
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
    }

    internal int Run()
    {
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
            if (version != ProtocolVersion)
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

            switch (type)
            {
                case "hello":
                    HandleHello(requestId.Value, request);
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

    private void HandleHello(ulong requestId,
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
        bool supported = false;
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
            supported |= version == ProtocolVersion;
        }
        if (count == 0 || !supported)
        {
            throw Fault("unsupported_version",
                "no supported helper protocol version was offered", false);
        }

        negotiated = true;
        Dictionary<string, object> response = Response(requestId, "hello");
        response["selected_protocol_version"] = ProtocolVersion;
        response["helper_name"] = engine.HelperName;
        response["helper_version"] = "0.1.0";
        WriteFrame(response);
    }

    private void HandleSynthesize(ulong requestId,
        IDictionary<string, object> request)
    {
        RequireFields(request, "protocol_version", "request_id", "type",
            "text", "settings");
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
        RequireFields(settings, "voice_id", "rate", "pitch", "volume");
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
        synthesis.Volume = ReadNumber(settings, "volume", 0.0, 1.0);
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
        try
        {
            OmnivoxCaptureResult result = engine.Synthesize(synthesis.Text,
                synthesis.VoiceId, synthesis.Rate, synthesis.Pitch,
                synthesis.Volume);
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
            ValidateMarkers(markers, frameCount, synthesis.Text);
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
        }
        catch (Exception error)
        {
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
        ulong frameCount, string text)
    {
        if (markers == null || markers.Length > MaximumMarkers)
        {
            throw new InvalidOperationException(
                "native engine returned invalid or too many markers");
        }
        ulong textBytes = (ulong)Encoding.UTF8.GetByteCount(text);
        foreach (OmnivoxHelperMarker marker in markers)
        {
            if (marker == null || marker.FrameOffset > frameCount ||
                (marker.Kind != "word" && marker.Kind != "sentence" &&
                 marker.Kind != "phoneme" && marker.Kind != "native_index") ||
                marker.TextStart.HasValue != marker.TextLength.HasValue ||
                (marker.Value != null &&
                 Encoding.UTF8.GetByteCount(marker.Value) >
                    MaximumStringLength))
            {
                throw new InvalidOperationException(
                    "native engine returned an invalid marker");
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
        synthesis.Worker.Join(TimeSpan.FromSeconds(10));
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

    private static Dictionary<string, object> Response(ulong requestId,
        string type)
    {
        Dictionary<string, object> response =
            new Dictionary<string, object>();
        response["protocol_version"] = ProtocolVersion;
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
        response["protocol_version"] = ProtocolVersion;
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

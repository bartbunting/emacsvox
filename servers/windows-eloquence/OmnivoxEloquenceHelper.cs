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

/// <summary>
/// A 32-bit Eloquence worker for the Omnivox engine-helper protocol.
/// Standard output is reserved for newline-delimited JSON responses.
/// </summary>
internal sealed class OmnivoxEloquenceHelper
{
    private const int ProtocolVersion = 1;
    private const int MaximumFrameBytes = 1024 * 1024;
    private const int MaximumTextBytes = 256 * 1024;
    private const int MaximumAudioChunkBytes = 256 * 1024;
    private const int MaximumStringLength = 16 * 1024;
    private const string DefaultDll =
        @"C:\Program Files (x86)\Freedom Scientific\Shared\Eloquence\6.1\ECI.DLL";

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
        internal int Rate;
        internal volatile bool Cancelled;
        internal Thread Worker;
    }

    private sealed class Voice
    {
        internal string Id;
        internal string Name;
        internal string Gender;
    }

    private static readonly Voice[] Voices = new Voice[]
    {
        NewVoice("v1", "Adult male 1", "male"),
        NewVoice("v2", "Adult female 1", "female"),
        NewVoice("v3", "Child 1", null),
        NewVoice("v4", "Adult male 2", "male"),
        NewVoice("v5", "Adult male 3", "male"),
        NewVoice("v6", "Elderly female 2", "female"),
        NewVoice("v7", "Elderly female 1", "female"),
        NewVoice("v8", "Adult male 1 variant", "male")
    };

    private readonly OmnivoxEloquenceCapture engine;
    private readonly StreamReader input;
    private readonly StreamWriter output;
    private readonly JavaScriptSerializer json;
    private readonly object outputLock = new object();
    private readonly object stateLock = new object();
    private ActiveSynthesis active;
    private bool negotiated;
    private bool shuttingDown;

    private OmnivoxEloquenceHelper(OmnivoxEloquenceCapture engine)
    {
        this.engine = engine;
        input = new StreamReader(Console.OpenStandardInput(),
            new UTF8Encoding(false, true), false, 4096);
        output = new StreamWriter(Console.OpenStandardOutput(),
            new UTF8Encoding(false), 4096);
        output.AutoFlush = true;
        json = new JavaScriptSerializer();
        json.MaxJsonLength = MaximumFrameBytes;
        json.RecursionLimit = 32;
    }

    private static Voice NewVoice(string id, string name, string gender)
    {
        Voice voice = new Voice();
        voice.Id = id;
        voice.Name = name;
        voice.Gender = gender;
        return voice;
    }

    private int Run()
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

            // Counting a surrogate as three bytes is conservative for valid
            // four-byte UTF-8 pairs and keeps allocation bounded.
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
            object decoded = json.DeserializeObject(line);
            IDictionary<string, object> request = decoded as
                IDictionary<string, object>;
            if (request == null)
            {
                throw Fault("invalid_request",
                    "helper request must be a JSON object", false);
            }

            requestId = ReadRequestId(request);
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
        IEnumerable values = value as IEnumerable;
        if (values == null || value is string)
        {
            throw Fault("invalid_request",
                "supported_protocol_versions must be an array", false);
        }
        int count = 0;
        bool supportsVersion = false;
        HashSet<int> seen = new HashSet<int>();
        foreach (object item in values)
        {
            int version = ConvertInteger(item,
                "supported_protocol_versions");
            ++count;
            if (count > 16 || version <= 0 || !seen.Add(version))
            {
                throw Fault("invalid_request",
                    "supported_protocol_versions is invalid", false);
            }
            supportsVersion |= version == ProtocolVersion;
        }
        if (count == 0 || !supportsVersion)
        {
            throw Fault("unsupported_version",
                "no supported helper protocol version was offered", false);
        }

        negotiated = true;
        Dictionary<string, object> response = Response(requestId, "hello");
        response["selected_protocol_version"] = ProtocolVersion;
        response["helper_name"] = "Omnivox Eloquence x86 helper";
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
                "Eloquence text cannot contain a NUL character", false);
        }

        IDictionary<string, object> settings = Required(request, "settings")
            as IDictionary<string, object>;
        if (settings == null)
        {
            throw Fault("invalid_parameter",
                "settings must be a JSON object", false);
        }
        RequireFields(settings, "voice_id", "rate", "pitch", "volume");
        string voiceId = settings["voice_id"] == null ? "v1" :
            ReadString(settings, "voice_id", false);
        if (!HasVoice(voiceId))
        {
            throw Fault("voice_not_found",
                "Eloquence voice was not found: " + voiceId, false);
        }
        double normalizedRate = ReadNumber(settings, "rate", 0.0, 1.0);
        ReadNumber(settings, "pitch", 0.5, 2.0);
        ReadNumber(settings, "volume", 0.0, 1.0);

        ActiveSynthesis synthesis = new ActiveSynthesis();
        synthesis.RequestId = requestId;
        synthesis.Text = text;
        synthesis.VoiceId = voiceId;
        // Existing Emacsvox Eloquence operation treats 75 as its normal
        // speed.  Preserve that midpoint while providing a bounded range.
        synthesis.Rate = (int)Math.Round(20.0 + normalizedRate * 110.0,
            MidpointRounding.AwayFromZero);
        synthesis.Worker = new Thread(delegate() { SynthesisWorker(synthesis); });
        synthesis.Worker.Name = "omnivox-eloquence-synthesis";
        synthesis.Worker.IsBackground = true;

        lock (stateLock)
        {
            if (active != null)
            {
                throw Fault("busy",
                    "Eloquence permits one active synthesis", true);
            }
            active = synthesis;
        }

        Dictionary<string, object> started = Response(requestId,
            "synthesis_started");
        Dictionary<string, object> format = new Dictionary<string, object>();
        format["sample_rate"] = OmnivoxEloquenceCapture.SpeechSampleRate;
        format["channels"] = 1;
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
            byte[] audio = engine.Synthesize(synthesis.Text,
                synthesis.VoiceId, synthesis.Rate);
            if (synthesis.Cancelled)
            {
                WriteSimple(synthesis.RequestId, "synthesis_cancelled");
                return;
            }

            uint sequence = 0;
            for (int offset = 0; offset < audio.Length;
                offset += MaximumAudioChunkBytes)
            {
                int count = Math.Min(MaximumAudioChunkBytes,
                    audio.Length - offset);
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
            Dictionary<string, object> completed = Response(
                synthesis.RequestId, "synthesis_completed");
            completed["frame_count"] = (ulong)(audio.Length / 2);
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
        descriptor["id"] = "eloquence";
        descriptor["display_name"] = "Eloquence";
        descriptor["version"] = engine.Version;
        descriptor["availability"] = Status("available", null);
        descriptor["health"] = Status("healthy", null);

        Dictionary<string, object> capabilities =
            new Dictionary<string, object>();
        Dictionary<string, object> acss = new Dictionary<string, object>();
        acss["rate"] = true;
        acss["average_pitch"] = false;
        acss["pitch_range"] = false;
        acss["stress"] = false;
        acss["richness"] = false;
        acss["volume"] = false;
        capabilities["acss"] = acss;
        capabilities["audio_output"] = "buffered_pcm";
        capabilities["cancellation"] = "synthesis_and_playback";
        Dictionary<string, object> concurrency =
            new Dictionary<string, object>();
        concurrency["mode"] = "serialized";
        capabilities["concurrency"] = concurrency;
        Dictionary<string, object> markers =
            new Dictionary<string, object>();
        markers["word"] = false;
        markers["sentence"] = false;
        markers["phoneme"] = false;
        markers["native_index"] = false;
        capabilities["markers"] = markers;
        capabilities["language_switching"] = false;
        capabilities["native_extensions"] = new object[0];
        descriptor["capabilities"] = capabilities;

        object[] voices = new object[Voices.Length];
        for (int index = 0; index < Voices.Length; ++index)
        {
            Voice voice = Voices[index];
            Dictionary<string, object> item =
                new Dictionary<string, object>();
            Dictionary<string, object> id = new Dictionary<string, object>();
            id["engine_id"] = "eloquence";
            id["voice_id"] = voice.Id;
            item["id"] = id;
            item["display_name"] = voice.Name;
            item["language"] = "en-US";
            item["gender"] = voice.Gender;
            item["quality"] = "compact";
            item["availability"] = Status("available", null);
            voices[index] = item;
        }
        descriptor["voices"] = voices;
        descriptor["default_voice_id"] = "v1";

        Dictionary<string, object> response = Response(requestId,
            "descriptor");
        response["descriptor"] = descriptor;
        WriteFrame(response);
    }

    private static Dictionary<string, object> Status(string status,
        string reason)
    {
        Dictionary<string, object> value = new Dictionary<string, object>();
        value["status"] = status;
        if (reason != null)
        {
            value["reason"] = reason;
        }
        return value;
    }

    private static bool HasVoice(string voiceId)
    {
        foreach (Voice voice in Voices)
        {
            if (voice.Id == voiceId)
            {
                return true;
            }
        }
        return false;
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

    private static ulong ReadRequestId(IDictionary<string, object> values)
    {
        return ReadUnsigned(values, "request_id");
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
            using (OmnivoxEloquenceCapture engine =
                new OmnivoxEloquenceCapture(dllPath))
            {
                return new OmnivoxEloquenceHelper(engine).Run();
            }
        }
        catch (Exception error)
        {
            Console.Error.WriteLine("Omnivox Eloquence helper failed: " +
                error.Message);
            return 1;
        }
    }
}

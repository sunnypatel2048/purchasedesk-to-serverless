using System;
using System.IO;
using System.Text;
using Xunit;

namespace PurchaseDesk.Tests.Golden
{
    // The comparison itself must be able to fail, not only pass.
    public class GoldenRecorderTests : IDisposable
    {
        private readonly string _root = Path.Combine(Path.GetTempPath(), "golden-recorder-tests", Guid.NewGuid().ToString("N"));
        private readonly GoldenRecorder _recorder;

        public GoldenRecorderTests()
        {
            Directory.CreateDirectory(Path.Combine(_root, "golden"));
            _recorder = new GoldenRecorder(Path.Combine(_root, "golden"), Path.Combine(_root, "actual"));
        }

        [Fact]
        public void A_missing_golden_file_is_a_mismatch_not_a_pass()
        {
            _recorder.RecordText("a.json", "{}\n");
            Assert.Contains("no golden file yet", Assert.Single(_recorder.Mismatches));
            Assert.True(File.Exists(Path.Combine(_root, "actual", "a.json")));
        }

        [Fact]
        public void Changed_text_is_reported_with_its_line()
        {
            File.WriteAllText(Path.Combine(_root, "golden", "a.json"), "{\n  \"TotalAmount\": 6.7500\n}\n");
            _recorder.RecordText("a.json", "{\n  \"TotalAmount\": 6.75\n}\n");
            Assert.Contains("line 2", Assert.Single(_recorder.Mismatches));
        }

        [Fact]
        public void Crlf_and_lf_text_are_equal()
        {
            File.WriteAllText(Path.Combine(_root, "golden", "a.json"), "{\r\n  \"A\": 1\r\n}\r\n");
            _recorder.RecordText("a.json", "{\n  \"A\": 1\n}\n");
            Assert.Empty(_recorder.Mismatches);
        }

        [Fact]
        public void Bytes_must_match_exactly_including_line_endings()
        {
            File.WriteAllBytes(Path.Combine(_root, "golden", "a.csv"), Encoding.ASCII.GetBytes("A,B\r\n"));
            _recorder.RecordBytes("a.csv", Encoding.ASCII.GetBytes("A,B\n"));
            Assert.Contains("bytes differ from offset 3", Assert.Single(_recorder.Mismatches));
        }

        [Fact]
        public void Exact_parse_keeps_decimal_scale_and_date_strings()
        {
            var token = GoldenRecorder.ParseExact("{\"A\":150.1500,\"D\":\"2026-01-23T14:13:54.997\"}");
            var pretty = GoldenRecorder.Pretty(token);
            Assert.Contains("150.1500", pretty);
            Assert.Contains("\"2026-01-23T14:13:54.997\"", pretty);
        }

        [Fact]
        public void Normalize_replaces_versions_always_and_times_only_for_writes_with_the_right_shape()
        {
            var token = GoldenRecorder.ParseExact(
                "{\"Version\":\"AAAAAAAAB9E=\",\"OrderDate\":\"2026-11-21T17:50:09.123\",\"DecidedAt\":\"21/11/2026\"}");

            var read = GoldenRecorder.Normalize(token, timesAreNow: false);
            Assert.Equal("<rowversion>", (string)read["Version"]);
            Assert.Equal("2026-11-21T17:50:09.123", (string)read["OrderDate"]);

            var write = GoldenRecorder.Normalize(token, timesAreNow: true);
            Assert.Equal("<now>", (string)write["OrderDate"]);
            Assert.Equal("21/11/2026", (string)write["DecidedAt"]);  // wrong shape: left alone, so it would show as a diff
        }

        public void Dispose()
        {
            try { Directory.Delete(_root, true); } catch (IOException) { }
        }
    }
}

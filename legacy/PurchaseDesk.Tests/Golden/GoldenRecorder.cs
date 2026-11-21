using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace PurchaseDesk.Tests.Golden
{
    // Writes what the legacy system actually produced to the "actual" folder, and compares it with the committed
    // golden file of the same name. A missing golden file is a mismatch, never a pass: golden files are only ever
    // created by reviewing a recorded run and committing it.
    //   golden/          committed, the definition of "equivalent"
    //   actual folder    GOLDEN_ACTUAL_DIR, or artifacts/golden-actual; CI uploads it as a build artifact
    public sealed class GoldenRecorder
    {
        private static readonly UTF8Encoding Utf8NoBom = new UTF8Encoding(false);
        private readonly List<string> _mismatches = new List<string>();

        public GoldenRecorder(string goldenDir, string actualDir)
        {
            GoldenDir = goldenDir;
            ActualDir = actualDir;
        }

        public string GoldenDir { get; }
        public string ActualDir { get; }
        public IReadOnlyList<string> Mismatches => _mismatches;

        public static GoldenRecorder ForRepository()
        {
            var root = FindRepositoryRoot();
            var actual = Environment.GetEnvironmentVariable("GOLDEN_ACTUAL_DIR");
            return new GoldenRecorder(
                Path.Combine(root, "golden"),
                string.IsNullOrEmpty(actual) ? Path.Combine(root, "artifacts", "golden-actual") : actual);
        }

        // Text files (JSON): compared with line endings normalised, since Windows checkouts may use CRLF.
        public void RecordText(string relativePath, string content)
        {
            var actualPath = Write(relativePath, Utf8NoBom.GetBytes(content));
            var goldenPath = Path.Combine(GoldenDir, relativePath);
            if (!File.Exists(goldenPath))
            {
                _mismatches.Add(relativePath + ": no golden file yet (recorded to " + actualPath + ")");
                return;
            }

            var expected = Normalize(File.ReadAllText(goldenPath, Encoding.UTF8));
            var actual = Normalize(content);
            if (expected != actual)
                _mismatches.Add(relativePath + ": " + FirstDifference(expected, actual));
        }

        // Binary files (the export CSV): compared byte for byte, encoding and line endings included.
        public void RecordBytes(string relativePath, byte[] content)
        {
            var actualPath = Write(relativePath, content);
            var goldenPath = Path.Combine(GoldenDir, relativePath);
            if (!File.Exists(goldenPath))
            {
                _mismatches.Add(relativePath + ": no golden file yet (recorded to " + actualPath + ")");
                return;
            }

            var expected = File.ReadAllBytes(goldenPath);
            if (!expected.SequenceEqual(content))
            {
                var index = Enumerable.Range(0, Math.Min(expected.Length, content.Length))
                    .Where(i => expected[i] != content[i]).DefaultIfEmpty(Math.Min(expected.Length, content.Length)).First();
                _mismatches.Add(relativePath + ": bytes differ from offset " + index
                                + " (golden " + expected.Length + " bytes, actual " + content.Length + " bytes)");
            }
        }

        public string Report()
        {
            return _mismatches.Count + " golden mismatch(es):" + Environment.NewLine
                   + string.Join(Environment.NewLine, _mismatches.Select(m => "  " + m));
        }

        // ------------------------------------------------------------------ JSON helpers

        // Parses JSON exactly as written: decimals keep their scale (150.1500 stays 150.1500) and dates stay
        // the strings the API emitted. A default parse would turn them into doubles and DateTimes.
        public static JToken ParseExact(string json)
        {
            using (var reader = new JsonTextReader(new StringReader(json)))
            {
                reader.FloatParseHandling = FloatParseHandling.Decimal;
                reader.DateParseHandling = DateParseHandling.None;
                return JToken.ReadFrom(reader);
            }
        }

        public static string Pretty(JToken token)
        {
            return token.ToString(Formatting.Indented) + "\n";
        }

        private static readonly Regex DateShape = new Regex(@"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,7})?$");

        // Replaces only what cannot repeat between runs: every Version (a rowversion), and, in responses to
        // writes, OrderDate and DecidedAt (GETDATE). Times are replaced only if they have the expected shape,
        // so a format change still shows up as a difference.
        public static JToken Normalize(JToken token, bool timesAreNow)
        {
            var copy = token.DeepClone();
            foreach (var property in copy.SelectTokens("$..*").OfType<JValue>().Select(v => v.Parent).OfType<JProperty>().ToList())
            {
                if (property.Name == "Version" && property.Value.Type == JTokenType.String)
                {
                    property.Value = "<rowversion>";
                }
                else if (timesAreNow && (property.Name == "OrderDate" || property.Name == "DecidedAt")
                         && property.Value.Type == JTokenType.String && DateShape.IsMatch((string)property.Value))
                {
                    property.Value = "<now>";
                }
            }
            return copy;
        }

        // ------------------------------------------------------------------ internals

        private string Write(string relativePath, byte[] content)
        {
            var path = Path.Combine(ActualDir, relativePath);
            Directory.CreateDirectory(Path.GetDirectoryName(path));
            File.WriteAllBytes(path, content);
            return path;
        }

        private static string Normalize(string text)
        {
            return text.Replace("\r\n", "\n");
        }

        private static string FirstDifference(string expected, string actual)
        {
            var e = expected.Split('\n');
            var a = actual.Split('\n');
            for (var i = 0; i < Math.Max(e.Length, a.Length); i++)
            {
                var el = i < e.Length ? e[i] : "(end of file)";
                var al = i < a.Length ? a[i] : "(end of file)";
                if (el != al)
                    return "line " + (i + 1) + ": golden [" + el.Trim() + "] actual [" + al.Trim() + "]";
            }
            return "differs";
        }

        private static string FindRepositoryRoot()
        {
            var dir = new DirectoryInfo(AppDomain.CurrentDomain.BaseDirectory);
            while (dir != null)
            {
                if (Directory.Exists(Path.Combine(dir.FullName, ".git")) || File.Exists(Path.Combine(dir.FullName, ".git")))
                    return dir.FullName;
                dir = dir.Parent;
            }
            throw new InvalidOperationException("Could not find the repository root (no .git above the test assembly).");
        }
    }
}

using System;
using System.Collections.Generic;
using System.Data.SqlClient;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;
using Microsoft.VisualBasic.FileIO;
using PurchaseDesk.Export;
using PurchaseDesk.Web;
using Xunit;

namespace PurchaseDesk.Tests
{
    // The nightly export against the seed data. Days are chosen by query, not hard-coded, so the tests keep
    // working if the seed changes deliberately. The server's culture is en-US; tests set it explicitly so a
    // runner's own settings cannot change the result, and one test shows what a de-DE server would write.
    [Collection("api")]
    public class ExportTests
    {
        private static readonly Encoding Windows1252 = Encoding.GetEncoding(1252);

        public ExportTests(ApiFixture api)
        {
            Assert.NotNull(api);  // the fixture sets Settings.Current, which holds the connection string
        }

        [Fact]
        public void A_seed_day_has_a_header_and_one_row_per_approved_line()
        {
            var day = BusiestApprovalDay();
            var expected = Scalar(
                "SELECT COUNT(*) FROM dbo.PurchaseOrders o JOIN dbo.PurchaseOrderLines l ON l.PurchaseOrderId = o.Id " +
                "WHERE o.Status = 'Approved' AND o.DecidedAt >= @d AND o.DecidedAt < DATEADD(day, 1, @d)", day);
            Assert.True(expected > 0);

            var result = Run(day, "en-US");
            var rows = Parse(result.Path);

            Assert.Equal(expected, result.Rows);
            Assert.Equal(expected + 1, rows.Count);
            Assert.Equal(
                "OrderNumber,SupplierCode,SupplierName,ApprovedAt,ApprovedBy,LineNumber,Sku,Description,Quantity,UnitPrice,DiscountPercent,LineAmount,OrderTotal",
                string.Join(",", rows[0]));
            Assert.Equal(ExportRunner.FileNameFor(day), Path.GetFileName(result.Path));
        }

        [Fact]
        public void Descriptions_with_commas_are_quoted_and_every_row_parses_to_13_fields()
        {
            var result = Run(BusiestApprovalDay(), "en-US");
            var raw = File.ReadAllText(result.Path, Windows1252);

            Assert.Matches(new Regex("\"[^\"]+, pack of \\d+\""), raw);
            Assert.All(Parse(result.Path), row => Assert.Equal(13, row.Length));
        }

        [Fact]
        public void An_accented_supplier_name_is_written_in_the_ansi_code_page_not_utf8()
        {
            Assert.Equal(1252, ExportRunner.FileEncoding.CodePage);  // en-US Windows

            var day = Day(
                "SELECT TOP 1 CAST(DecidedAt AS date) FROM dbo.PurchaseOrders " +
                "WHERE SupplierId = 47 AND Status = 'Approved' ORDER BY DecidedAt");
            var bytes = File.ReadAllBytes(Run(day, "en-US").Path);

            Assert.True(Contains(bytes, new byte[] { 0x4D, 0xFC, 0x6C, 0x6C }), "expected 'M', 0xFC, 'l', 'l' (Windows-1252)");
            Assert.False(Contains(bytes, new byte[] { 0xC3, 0xBC }), "found UTF-8 bytes for u-umlaut");
        }

        [Fact]
        public void Under_en_US_dates_and_amounts_use_us_formats()
        {
            var row = Parse(Run(BusiestApprovalDay(), "en-US").Path)[1];

            Assert.Matches(@"^\d{1,2}/\d{1,2}/\d{4} \d{1,2}:\d{2}:\d{2} (AM|PM)$", row[3]);  // ApprovedAt
            Assert.Matches(@"^\d+\.\d{4}$", row[9]);   // UnitPrice: money, four decimals
            Assert.Matches(@"^\d+\.\d{2}$", row[10]);  // DiscountPercent: decimal(5,2)
        }

        [Fact]
        public void Under_de_DE_the_same_amounts_use_a_comma_and_get_quoted()
        {
            var result = Run(BusiestApprovalDay(), "de-DE");
            var raw = File.ReadAllText(result.Path, Windows1252);
            var row = Parse(result.Path)[1];

            Assert.Matches(@"^\d+,\d{4}$", row[9]);                    // 150,1500
            Assert.Matches(@"^\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2}$", row[3]);  // 02.03.2026 09:15:03
            Assert.Matches(new Regex(",\"\\d+,\\d{4}\","), raw);       // quoted because of the comma
        }

        [Fact]
        public void A_day_with_no_approvals_writes_only_the_header()
        {
            var result = Run(new DateTime(2025, 1, 1), "en-US");
            Assert.Equal(0, result.Rows);
            Assert.Single(Parse(result.Path));
        }

        private static ExportResult Run(DateTime day, string culture)
        {
            var folder = Path.Combine(Path.GetTempPath(), "purchasedesk-export-tests", Guid.NewGuid().ToString("N"));
            var previous = Thread.CurrentThread.CurrentCulture;
            Thread.CurrentThread.CurrentCulture = new CultureInfo(culture);
            try
            {
                return new ExportRunner(Settings.Current.ConnectionString, folder).Run(day);
            }
            finally
            {
                Thread.CurrentThread.CurrentCulture = previous;
            }
        }

        private static List<string[]> Parse(string path)
        {
            var rows = new List<string[]>();
            using (var parser = new TextFieldParser(path, Windows1252))
            {
                parser.TextFieldType = FieldType.Delimited;
                parser.SetDelimiters(",");
                parser.HasFieldsEnclosedInQuotes = true;
                while (!parser.EndOfData)
                    rows.Add(parser.ReadFields());
            }
            return rows;
        }

        private static DateTime BusiestApprovalDay()
        {
            return Day(
                "SELECT TOP 1 CAST(DecidedAt AS date) FROM dbo.PurchaseOrders WHERE Status = 'Approved' " +
                "AND DecidedAt < '2026-11-01' GROUP BY CAST(DecidedAt AS date) ORDER BY COUNT(*) DESC, CAST(DecidedAt AS date)");
        }

        private static DateTime Day(string sql)
        {
            using (var connection = new SqlConnection(Settings.Current.ConnectionString))
            using (var command = new SqlCommand(sql, connection))
            {
                connection.Open();
                var value = command.ExecuteScalar();
                Assert.True(value != null && value != DBNull.Value, "no day found for: " + sql);
                return (DateTime)value;
            }
        }

        private static int Scalar(string sql, DateTime day)
        {
            using (var connection = new SqlConnection(Settings.Current.ConnectionString))
            using (var command = new SqlCommand(sql, connection))
            {
                command.Parameters.AddWithValue("@d", day);
                connection.Open();
                return (int)command.ExecuteScalar();
            }
        }

        private static bool Contains(byte[] haystack, byte[] needle)
        {
            for (var i = 0; i <= haystack.Length - needle.Length; i++)
            {
                if (!needle.Where((b, j) => haystack[i + j] != b).Any())
                    return true;
            }
            return false;
        }
    }
}

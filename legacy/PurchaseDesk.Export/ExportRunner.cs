using System;
using System.Data;
using System.Data.SqlClient;
using System.Globalization;
using System.IO;
using System.Text;

namespace PurchaseDesk.Export
{
    public sealed class ExportResult
    {
        public string Path { get; set; }
        public int Rows { get; set; }
    }

    // Writes one day's approved order lines (usp_ExportApprovedOrders) to approved-orders-yyyyMMdd.csv.
    // Legacy behaviour the migration must keep or consciously change:
    //   * Values are formatted with the server's current culture (en-US: 3/2/2026 9:15:03 AM, 150.1500).
    //     On a different culture the same data comes out differently (de-DE: 150,1500).
    //   * The file is written in the server's ANSI code page (Encoding.Default, Windows-1252 on en-US Windows),
    //     not UTF-8: 'Mueller' with u-umlaut is the single byte 0xFC.
    //   * Lines end with the platform newline (CRLF on Windows). A rerun overwrites the file.
    public sealed class ExportRunner
    {
        public const string FilePrefix = "approved-orders-";

        private readonly string _connectionString;
        private readonly string _exportFolder;

        public ExportRunner(string connectionString, string exportFolder)
        {
            _connectionString = connectionString;
            _exportFolder = exportFolder;
        }

        // The server's ANSI code page. Deliberately not UTF-8: that is how the legacy file has always been written.
        public static Encoding FileEncoding
        {
            get { return Encoding.Default; }
        }

        public static string FileNameFor(DateTime day)
        {
            return FilePrefix + day.ToString("yyyyMMdd", CultureInfo.InvariantCulture) + ".csv";
        }

        public ExportResult Run(DateTime day)
        {
            var from = day.Date;
            var to = from.AddDays(1);

            Directory.CreateDirectory(_exportFolder);
            var path = Path.Combine(_exportFolder, FileNameFor(from));
            var rows = 0;

            using (var connection = new SqlConnection(_connectionString))
            using (var command = new SqlCommand("dbo.usp_ExportApprovedOrders", connection))
            {
                command.CommandType = CommandType.StoredProcedure;
                command.CommandTimeout = 120;
                command.Parameters.Add("@From", SqlDbType.DateTime).Value = from;
                command.Parameters.Add("@To", SqlDbType.DateTime).Value = to;
                connection.Open();

                using (var reader = command.ExecuteReader())
                using (var writer = new StreamWriter(path, false, FileEncoding))
                {
                    var header = new string[reader.FieldCount];
                    for (var i = 0; i < reader.FieldCount; i++)
                        header[i] = Csv.Field(reader.GetName(i));
                    writer.WriteLine(string.Join(",", header));

                    while (reader.Read())
                    {
                        var fields = new string[reader.FieldCount];
                        for (var i = 0; i < reader.FieldCount; i++)
                        {
                            // Convert.ToString uses the current culture: the server's regional settings decide
                            // how dates and amounts look.
                            fields[i] = Csv.Field(reader.IsDBNull(i) ? string.Empty : Convert.ToString(reader.GetValue(i)));
                        }
                        writer.WriteLine(string.Join(",", fields));
                        rows++;
                    }
                }
            }

            return new ExportResult { Path = path, Rows = rows };
        }
    }

    public static class Csv
    {
        // Quotes a field when it contains a comma, a quote or a line break, doubling any quotes inside.
        public static string Field(string value)
        {
            if (value.IndexOfAny(new[] { ',', '"', '\r', '\n' }) < 0)
                return value;
            return "\"" + value.Replace("\"", "\"\"") + "\"";
        }
    }
}

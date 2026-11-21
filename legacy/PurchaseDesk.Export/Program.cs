using System;
using System.Configuration;
using System.Globalization;
using System.IO;

namespace PurchaseDesk.Export
{
    // Run nightly by a Windows Scheduled Task:
    //   PurchaseDesk.Export.exe                     exports yesterday, by the server's local clock
    //   PurchaseDesk.Export.exe --date 2026-03-02   exports that day (reruns, backfills)
    // Exit codes: 0 success, 1 failure, 2 bad arguments.
    public static class Program
    {
        public static int Main(string[] args)
        {
            DateTime day;
            if (!TryParseDay(args, out day))
            {
                Console.Error.WriteLine("Usage: PurchaseDesk.Export.exe [--date yyyy-MM-dd]");
                return 2;
            }

            var logFolder = ConfigurationManager.AppSettings["LogFolder"] ?? AppDomain.CurrentDomain.BaseDirectory;
            try
            {
                var connection = ConfigurationManager.ConnectionStrings["PurchaseDesk"];
                if (connection == null)
                    throw new ConfigurationErrorsException("The PurchaseDesk connection string is missing from App.config.");
                var exportFolder = ConfigurationManager.AppSettings["ExportFolder"];
                if (string.IsNullOrEmpty(exportFolder))
                    throw new ConfigurationErrorsException("ExportFolder is missing from App.config.");

                var result = new ExportRunner(connection.ConnectionString, exportFolder).Run(day);

                var message = "Exported " + result.Rows + " rows for " + day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture)
                              + " to " + result.Path;
                Log(logFolder, "INFO", message);
                Console.WriteLine(message);
                return 0;
            }
            catch (Exception ex)
            {
                Log(logFolder, "ERROR", "Export for " + day.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) + " failed: " + ex);
                Console.Error.WriteLine(ex);
                return 1;
            }
        }

        public static bool TryParseDay(string[] args, out DateTime day)
        {
            day = DateTime.Today.AddDays(-1);  // the server's local clock decides what "yesterday" is
            if (args.Length == 0)
                return true;
            return args.Length == 2
                   && args[0] == "--date"
                   && DateTime.TryParseExact(args[1], "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out day);
        }

        // One line per run in <LogFolder>\export-yyyyMMdd.log, server local time. Never fails the export.
        private static void Log(string folder, string level, string message)
        {
            try
            {
                var now = DateTime.Now;
                Directory.CreateDirectory(folder);
                File.AppendAllText(
                    Path.Combine(folder, "export-" + now.ToString("yyyyMMdd", CultureInfo.InvariantCulture) + ".log"),
                    now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture) + " " + level + " " + message
                    + Environment.NewLine);
            }
            catch (IOException)
            {
            }
            catch (UnauthorizedAccessException)
            {
            }
        }
    }
}

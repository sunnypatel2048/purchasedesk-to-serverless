using System;
using System.Globalization;
using System.IO;

namespace PurchaseDesk.Web.Infrastructure
{
    // Appends lines to <LogFolder>\app-yyyyMMdd.log on the server's own disk, in server local time.
    // A legacy trait: the migration replaces it with structured JSON logs in CloudWatch.
    // Logging must never break a request, so write failures are swallowed.
    public static class FileLog
    {
        private static readonly object Gate = new object();

        public static void Write(string level, string message)
        {
            try
            {
                var now = DateTime.Now;
                var folder = Settings.Current.LogFolder;
                var path = Path.Combine(folder, "app-" + now.ToString("yyyyMMdd", CultureInfo.InvariantCulture) + ".log");
                var line = now.ToString("yyyy-MM-dd HH:mm:ss.fff", CultureInfo.InvariantCulture) + " " + level + " " + message
                           + Environment.NewLine;

                lock (Gate)
                {
                    Directory.CreateDirectory(folder);
                    File.AppendAllText(path, line);
                }
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

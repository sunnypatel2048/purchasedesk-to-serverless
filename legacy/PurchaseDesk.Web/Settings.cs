using System;
using System.Configuration;
using System.Globalization;

namespace PurchaseDesk.Web
{
    // Values from Web.config. Tests set Settings.Current directly instead.
    public sealed class Settings
    {
        private static Settings _current;

        public string ConnectionString { get; set; }
        public string ApiKey { get; set; }
        public decimal ApprovalLimit { get; set; }
        public string LogFolder { get; set; }

        public static Settings Current
        {
            get { return _current ?? (_current = FromConfig()); }
            set { _current = value; }
        }

        public static Settings FromConfig()
        {
            var connection = ConfigurationManager.ConnectionStrings["PurchaseDesk"];
            if (connection == null)
                throw new ConfigurationErrorsException("The PurchaseDesk connection string is missing from Web.config.");

            return new Settings
            {
                ConnectionString = connection.ConnectionString,
                ApiKey = ConfigurationManager.AppSettings["ApiKey"],
                ApprovalLimit = decimal.Parse(
                    ConfigurationManager.AppSettings["ApprovalLimit"] ?? "0", NumberStyles.Number, CultureInfo.InvariantCulture),
                LogFolder = ConfigurationManager.AppSettings["LogFolder"] ?? AppDomain.CurrentDomain.BaseDirectory,
            };
        }
    }
}

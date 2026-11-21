using System;
using System.Data;
using System.Data.SqlClient;

namespace PurchaseDesk.Web.Data
{
    // Plain ADO.NET: a connection per call, stored procedures only, synchronous.
    internal static class Db
    {
        public static SqlConnection Open()
        {
            var connection = new SqlConnection(Settings.Current.ConnectionString);
            connection.Open();
            return connection;
        }

        public static SqlCommand Procedure(SqlConnection connection, string name)
        {
            return new SqlCommand(name, connection) { CommandType = CommandType.StoredProcedure, CommandTimeout = 30 };
        }

        public static object OrDbNull(object value)
        {
            return value ?? DBNull.Value;
        }
    }

    internal static class DataRecordExtensions
    {
        public static int Int(this IDataRecord r, string name) => r.GetInt32(r.GetOrdinal(name));
        public static short Short(this IDataRecord r, string name) => r.GetInt16(r.GetOrdinal(name));
        public static bool Bool(this IDataRecord r, string name) => r.GetBoolean(r.GetOrdinal(name));
        public static decimal Decimal(this IDataRecord r, string name) => r.GetDecimal(r.GetOrdinal(name));
        public static DateTime DateTime(this IDataRecord r, string name) => r.GetDateTime(r.GetOrdinal(name));
        public static byte[] Bytes(this IDataRecord r, string name) => (byte[])r.GetValue(r.GetOrdinal(name));

        public static string StringOrNull(this IDataRecord r, string name)
        {
            var i = r.GetOrdinal(name);
            return r.IsDBNull(i) ? null : r.GetString(i);
        }

        public static DateTime? DateTimeOrNull(this IDataRecord r, string name)
        {
            var i = r.GetOrdinal(name);
            return r.IsDBNull(i) ? (DateTime?)null : r.GetDateTime(i);
        }
    }
}

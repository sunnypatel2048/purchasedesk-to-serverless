using System.Data;
using System.Data.SqlClient;

namespace Spike.Web
{
    // Data access in the legacy style: ADO.NET calling a stored procedure, no ORM.
    public static class SpikeDb
    {
        public static decimal RoundAmount(string connectionString, decimal amount)
        {
            using (var connection = new SqlConnection(connectionString))
            using (var command = new SqlCommand("dbo.usp_RoundAmount", connection))
            {
                command.CommandType = CommandType.StoredProcedure;
                command.Parameters.Add("@Amount", SqlDbType.Decimal).Value = amount;
                command.Parameters["@Amount"].Precision = 19;
                command.Parameters["@Amount"].Scale = 4;

                connection.Open();
                return (decimal)command.ExecuteScalar();
            }
        }
    }
}

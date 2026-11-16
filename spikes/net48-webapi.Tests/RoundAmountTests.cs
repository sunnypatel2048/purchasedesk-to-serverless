using System;
using Xunit;

namespace Spike.Web.Tests
{
    public class RoundAmountTests
    {
        // Set by CI. Windows authentication, so no password is stored anywhere.
        private static readonly string ConnectionString =
            Environment.GetEnvironmentVariable("SPIKE_SQL_CONNECTION")
            ?? throw new InvalidOperationException("Set SPIKE_SQL_CONNECTION to a SQL Server connection string.");

        [Fact]
        public void Stored_procedure_rounds_half_away_from_zero()
        {
            var rounded = SpikeDb.RoundAmount(ConnectionString, 2.5m);

            Assert.Equal(3m, rounded);
            // The C# default disagrees, which is why the migration needs parity tests.
            Assert.Equal(2m, Math.Round(2.5m));
        }
    }
}

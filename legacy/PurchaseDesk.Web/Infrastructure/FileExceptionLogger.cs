using System.Data.SqlClient;
using System.Web.Http.ExceptionHandling;

namespace PurchaseDesk.Web.Infrastructure
{
    // Web API calls exception loggers before exception filters, so expected business errors (the procedures'
    // 5000x codes) arrive here too. They are logged as WARN; everything else as ERROR with the full exception.
    public class FileExceptionLogger : ExceptionLogger
    {
        public override void Log(ExceptionLoggerContext context)
        {
            var request = context.Request;
            var where = request == null ? "(no request)" : request.Method + " " + request.RequestUri.PathAndQuery;
            var sql = context.Exception as SqlException;

            if (sql != null && SqlErrorExceptionFilter.IsExpected(sql))
                FileLog.Write("WARN", where + " " + sql.Number + " " + sql.Message);
            else
                FileLog.Write("ERROR", where + " " + context.Exception);
        }
    }
}

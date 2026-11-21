using System.Data.SqlClient;
using System.Net;
using System.Net.Http;
using System.Web.Http.Filters;

namespace PurchaseDesk.Web.Infrastructure
{
    // Maps the stored procedures' THROW numbers to HTTP statuses. Anything else stays a 500.
    public class SqlErrorExceptionFilter : ExceptionFilterAttribute
    {
        public override void OnException(HttpActionExecutedContext context)
        {
            var sql = context.Exception as SqlException;
            if (sql == null)
                return;

            HttpStatusCode status;
            string message;
            if (!TryMap(sql, out status, out message))
                return;

            context.Response = context.Request.CreateErrorResponse(status, message);
        }

        public static bool IsExpected(SqlException sql)
        {
            HttpStatusCode status;
            string message;
            return TryMap(sql, out status, out message);
        }

        private static bool TryMap(SqlException sql, out HttpStatusCode status, out string message)
        {
            message = sql.Message;
            switch (sql.Number)
            {
                case 50001: status = HttpStatusCode.BadRequest; return true;   // invalid input
                case 50002: status = HttpStatusCode.NotFound; return true;     // not found, or supplier inactive
                case 50003: status = HttpStatusCode.Conflict; return true;     // RowVer mismatch
                case 50004: status = HttpStatusCode.Conflict; return true;     // no longer Pending
                case 50005: status = (HttpStatusCode)422; return true;         // over the approval limit
                case 2628:                                                     // string would be truncated (2019+)
                case 8152:                                                     // string would be truncated (older)
                    status = HttpStatusCode.BadRequest;
                    message = "A value is longer than the field allows.";
                    return true;
                default:
                    status = HttpStatusCode.InternalServerError;
                    return false;
            }
        }
    }
}

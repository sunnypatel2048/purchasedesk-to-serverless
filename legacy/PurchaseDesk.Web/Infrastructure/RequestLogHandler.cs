using System.Diagnostics;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;

namespace PurchaseDesk.Web.Infrastructure
{
    // One log line per request: method, path and query, status, elapsed milliseconds.
    public class RequestLogHandler : DelegatingHandler
    {
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            var timer = Stopwatch.StartNew();
            var response = await base.SendAsync(request, cancellationToken);
            FileLog.Write("INFO", request.Method + " " + request.RequestUri.PathAndQuery + " "
                                  + (int)response.StatusCode + " " + timer.ElapsedMilliseconds + "ms");
            return response;
        }
    }
}

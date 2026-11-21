using System.Web.Http;
using System.Web.Http.ExceptionHandling;
using PurchaseDesk.Web.Infrastructure;

namespace PurchaseDesk.Web
{
    // Used by IIS (Global.asax) and by the in-memory test host alike, so nothing here may touch HttpContext.Current.
    public static class WebApiConfig
    {
        public static void Register(HttpConfiguration config)
        {
            config.MapHttpAttributeRoutes();

            config.Filters.Add(new ApiKeyAuthorizationFilter());
            config.Filters.Add(new SqlErrorExceptionFilter());
            config.MessageHandlers.Add(new RequestLogHandler());
            config.Services.Add(typeof(IExceptionLogger), new FileExceptionLogger());

            // JSON only. Otherwise Web API 2's defaults stand: Newtonsoft.Json, PascalCase property names,
            // dates without a time zone, nulls included. The new API has to match them or change them on purpose.
            config.Formatters.Remove(config.Formatters.XmlFormatter);
        }
    }
}

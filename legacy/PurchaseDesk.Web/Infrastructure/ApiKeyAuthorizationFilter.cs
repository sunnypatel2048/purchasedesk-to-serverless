using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Web.Http.Controllers;
using System.Web.Http.Filters;

namespace PurchaseDesk.Web.Infrastructure
{
    // One shared API key for every caller, compared with plain string equality. Weak by design: a legacy trait,
    // documented as such and replaced by Cognito tokens in the migration.
    public class ApiKeyAuthorizationFilter : AuthorizationFilterAttribute
    {
        public const string HeaderName = "X-Api-Key";

        public override void OnAuthorization(HttpActionContext actionContext)
        {
            IEnumerable<string> values;
            var supplied = actionContext.Request.Headers.TryGetValues(HeaderName, out values) ? values.FirstOrDefault() : null;
            var expected = Settings.Current.ApiKey;

            if (string.IsNullOrEmpty(expected) || supplied != expected)
            {
                actionContext.Response = actionContext.Request.CreateErrorResponse(
                    HttpStatusCode.Unauthorized, "A valid X-Api-Key header is required.");
            }
        }
    }
}

using System.Web;
using System.Web.Http;

namespace PurchaseDesk.Web
{
    // IIS creates this class through Global.asax when the application starts.
    public class WebApiApplication : HttpApplication
    {
        protected void Application_Start()
        {
            GlobalConfiguration.Configure(WebApiConfig.Register);
        }
    }
}

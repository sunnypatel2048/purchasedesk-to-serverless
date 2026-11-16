using System.Web;
using System.Web.Http;

namespace Spike.Web
{
    // IIS creates this class through Global.asax when the application starts.
    public class WebApiApplication : HttpApplication
    {
        protected void Application_Start()
        {
            GlobalConfiguration.Configure(config =>
            {
                config.MapHttpAttributeRoutes();
            });
        }
    }

    public class PingController : ApiController
    {
        [HttpGet]
        [Route("api/ping")]
        public IHttpActionResult Get()
        {
            return Ok(new { status = "ok", framework = System.Environment.Version.ToString() });
        }
    }
}

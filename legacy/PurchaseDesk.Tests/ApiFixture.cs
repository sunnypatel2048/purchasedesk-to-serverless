using System;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading.Tasks;
using System.Web.Http;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using PurchaseDesk.Web;
using PurchaseDesk.Web.Infrastructure;
using Xunit;

namespace PurchaseDesk.Tests
{
    // Hosts the real Web API pipeline in memory: the same WebApiConfig.Register that IIS uses, with no IIS.
    public sealed class ApiFixture : IDisposable
    {
        public const string ApiKey = "test-api-key";
        public const decimal ApprovalLimit = 25000m;

        private readonly HttpServer _server;

        public ApiFixture()
        {
            Settings.Current = new Settings
            {
                ConnectionString = Environment.GetEnvironmentVariable("PURCHASEDESK_SQL")
                                   ?? "Server=localhost;Database=PurchaseDesk;Integrated Security=true",
                ApiKey = ApiKey,
                ApprovalLimit = ApprovalLimit,
                LogFolder = Path.Combine(Path.GetTempPath(), "purchasedesk-tests"),
            };

            var config = new HttpConfiguration();
            WebApiConfig.Register(config);
            // In-memory requests count as local, and Web API shows local callers exception details. Real clients
            // reach IIS remotely and never see them, so the tests (and the golden files) see what they would.
            config.IncludeErrorDetailPolicy = IncludeErrorDetailPolicy.Never;
            config.EnsureInitialized();
            _server = new HttpServer(config);

            Client = new HttpClient(_server, disposeHandler: false) { BaseAddress = new Uri("http://localhost/") };
            Client.DefaultRequestHeaders.Add(ApiKeyAuthorizationFilter.HeaderName, ApiKey);
        }

        public HttpClient Client { get; }

        public HttpClient ClientWithoutKey()
        {
            return new HttpClient(_server, disposeHandler: false) { BaseAddress = new Uri("http://localhost/") };
        }

        public static StringContent Json(object body)
        {
            return new StringContent(JsonConvert.SerializeObject(body), Encoding.UTF8, "application/json");
        }

        public static async Task<JToken> ReadAsync(HttpResponseMessage response)
        {
            return JToken.Parse(await response.Content.ReadAsStringAsync());
        }

        public void Dispose()
        {
            Client.Dispose();
            _server.Dispose();
        }
    }

    [CollectionDefinition("api")]
    public class ApiCollection : ICollectionFixture<ApiFixture>
    {
    }
}

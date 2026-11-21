using System.Net;
using System.Net.Http;
using System.Threading.Tasks;
using Newtonsoft.Json.Linq;
using Xunit;

namespace PurchaseDesk.Tests
{
    // One or more checks per route against the seed data, plus the API key and the error mapping.
    // Tests that create or decide orders change the database; CI checks the seed before running them.
    [Collection("api")]
    public class SmokeTests
    {
        private readonly ApiFixture _api;

        public SmokeTests(ApiFixture api)
        {
            _api = api;
        }

        [Fact]
        public async Task Missing_or_wrong_api_key_is_401()
        {
            using (var client = _api.ClientWithoutKey())
            {
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("api/suppliers")).StatusCode);

                client.DefaultRequestHeaders.Add("X-Api-Key", "wrong-key");
                Assert.Equal(HttpStatusCode.Unauthorized, (await client.GetAsync("api/suppliers")).StatusCode);
            }
        }

        [Fact]
        public async Task Suppliers_list_is_the_46_active_ones_in_collation_order_with_pascal_case_json()
        {
            var response = await _api.Client.GetAsync("api/suppliers");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);

            var raw = await response.Content.ReadAsStringAsync();
            Assert.Contains("\"IsActive\":", raw);  // Web API 2 default: PascalCase

            var suppliers = (JArray)JToken.Parse(raw);
            Assert.Equal(46, suppliers.Count);
            Assert.Equal(49, (int)suppliers[0]["Id"]);  // Angstrom Labs sorts first
        }

        [Fact]
        public async Task Supplier_by_id_is_200_or_404()
        {
            var found = await _api.Client.GetAsync("api/suppliers/47");
            Assert.Equal(HttpStatusCode.OK, found.StatusCode);
            Assert.Equal("S047", (string)(await ApiFixture.ReadAsync(found))["Code"]);

            Assert.Equal(HttpStatusCode.NotFound, (await _api.Client.GetAsync("api/suppliers/999")).StatusCode);
        }

        [Fact]
        public async Task Search_pending_returns_the_total_and_a_page_of_25()
        {
            var response = await _api.Client.GetAsync("api/purchase-orders?status=Pending&pageSize=25");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);

            var body = await ApiFixture.ReadAsync(response);
            Assert.True((int)body["TotalCount"] >= 518);  // 518 in the seed; other tests add Pending orders
            Assert.Equal(25, ((JArray)body["Items"]).Count);
        }

        [Fact]
        public async Task Search_with_a_bad_sort_is_400_with_the_procedure_message()
        {
            var response = await _api.Client.GetAsync("api/purchase-orders?sort=Supplier");
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
            Assert.Contains("SortBy must be", (string)(await ApiFixture.ReadAsync(response))["Message"]);
        }

        [Fact]
        public async Task Order_14_has_its_planted_half_cent_line_rounded_up_and_a_version()
        {
            var response = await _api.Client.GetAsync("api/purchase-orders/14");
            Assert.Equal(HttpStatusCode.OK, response.StatusCode);

            var order = await ApiFixture.ReadAsync(response);
            Assert.Equal("PO-000014", (string)order["OrderNumber"]);
            var line3 = ((JArray)order["Lines"])[2];
            Assert.Equal(150.15m, (decimal)line3["LineAmount"]);  // 1 x 150.1450 -> 150.145 -> 150.15
            Assert.False(string.IsNullOrEmpty((string)order["Version"]));

            Assert.Equal(HttpStatusCode.NotFound, (await _api.Client.GetAsync("api/purchase-orders/999999")).StatusCode);
        }

        [Fact]
        public async Task Create_returns_201_with_location_and_t_sql_rounding()
        {
            var response = await CreateAsync(
                Line("SKU-SMOKE-1", 1, 2.3450m, 0m),     // 2.345    -> 2.35
                Line("SKU-SMOKE-2", 3, 1.6750m, 12.5m)); // 4.396875 -> 4.40

            Assert.Equal(HttpStatusCode.Created, response.StatusCode);
            var order = await ApiFixture.ReadAsync(response);
            Assert.EndsWith("/api/purchase-orders/" + (int)order["Id"], response.Headers.Location.ToString());
            Assert.Equal("Pending", (string)order["Status"]);
            Assert.Equal(2.35m, (decimal)order["Lines"][0]["LineAmount"]);
            Assert.Equal(4.40m, (decimal)order["Lines"][1]["LineAmount"]);
            Assert.Equal(6.75m, (decimal)order["TotalAmount"]);
        }

        [Fact]
        public async Task Create_for_a_missing_supplier_is_404()
        {
            var body = new { SupplierId = 999, CreatedBy = "smoke.test", Lines = new[] { Line("SKU-SMOKE-1", 1, 1m, 0m) } };
            var response = await _api.Client.PostAsync("api/purchase-orders", ApiFixture.Json(body));
            Assert.Equal(HttpStatusCode.NotFound, response.StatusCode);
            Assert.Contains("Supplier not found or inactive", (string)(await ApiFixture.ReadAsync(response))["Message"]);
        }

        [Fact]
        public async Task Approve_then_approve_again_with_the_old_version_is_409()
        {
            var order = await ApiFixture.ReadAsync(await CreateAsync(Line("SKU-SMOKE-3", 2, 10m, 0m)));
            var id = (int)order["Id"];
            var decision = ApiFixture.Json(new { DecidedBy = "smoke.approver", Version = (string)order["Version"] });

            var approved = await _api.Client.PostAsync("api/purchase-orders/" + id + "/approve", decision);
            Assert.Equal(HttpStatusCode.OK, approved.StatusCode);
            Assert.Equal("Approved", (string)(await ApiFixture.ReadAsync(approved))["Status"]);

            var again = await _api.Client.PostAsync("api/purchase-orders/" + id + "/approve",
                ApiFixture.Json(new { DecidedBy = "smoke.approver", Version = (string)order["Version"] }));
            Assert.Equal(HttpStatusCode.Conflict, again.StatusCode);
        }

        [Fact]
        public async Task Approving_over_the_limit_is_422_but_rejecting_is_allowed()
        {
            // 200 x 150.00 = 30,000, over the 25,000 limit.
            var order = await ApiFixture.ReadAsync(await CreateAsync(Line("SKU-SMOKE-4", 200, 150m, 0m)));
            var id = (int)order["Id"];
            var version = (string)order["Version"];

            var approve = await _api.Client.PostAsync("api/purchase-orders/" + id + "/approve",
                ApiFixture.Json(new { DecidedBy = "smoke.approver", Version = version }));
            Assert.Equal((HttpStatusCode)422, approve.StatusCode);

            var reject = await _api.Client.PostAsync("api/purchase-orders/" + id + "/reject",
                ApiFixture.Json(new { DecidedBy = "smoke.approver", Version = version }));
            Assert.Equal(HttpStatusCode.OK, reject.StatusCode);
            Assert.Equal("Rejected", (string)(await ApiFixture.ReadAsync(reject))["Status"]);
        }

        [Fact]
        public async Task Decision_without_a_version_is_400()
        {
            var response = await _api.Client.PostAsync("api/purchase-orders/14/approve",
                ApiFixture.Json(new { DecidedBy = "smoke.approver" }));
            Assert.Equal(HttpStatusCode.BadRequest, response.StatusCode);
        }

        private Task<HttpResponseMessage> CreateAsync(params object[] lines)
        {
            var body = new { SupplierId = 1, CreatedBy = "smoke.test", Notes = "Smoke test", Lines = lines };
            return _api.Client.PostAsync("api/purchase-orders", ApiFixture.Json(body));
        }

        private static object Line(string sku, int quantity, decimal unitPrice, decimal discountPercent)
        {
            return new { Sku = sku, Description = "Smoke test line", Quantity = quantity, UnitPrice = unitPrice, DiscountPercent = discountPercent };
        }
    }
}

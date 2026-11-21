using System;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using PurchaseDesk.Export;
using PurchaseDesk.Web;
using Xunit;

namespace PurchaseDesk.Tests.Golden
{
    // Records every legacy response into golden/ and fails if any would change. These files are the definition of
    // "equivalent" for the new system.
    //
    // Must run first, against a freshly loaded database (CI runs it alone, right after loading): writes assume the
    // next order id is 2001, and searches assume no orders beyond the seed. One test plays every scenario in a fixed
    // order (reads, then writes, then the export) and reports all mismatches at the end.
    // Order ids and days below were chosen by querying the seed: 14 has a planted half-cent line, 125 and 250 the
    // .997/.003 ms times, 1 an upper-case URGENT note, 4 the first NULL RequiredBy, 9 the first rejection, 49 the
    // first order from supplier 47 (Mueller GmbH); supplier 2 is inactive; 2026-05-27 is the busiest approval day
    // and 2026-01-14 supplier 47's first approval.
    [Collection("api")]
    public class CharacterizationTests
    {
        private readonly ApiFixture _api;
        private GoldenRecorder _golden;

        public CharacterizationTests(ApiFixture api)
        {
            _api = api;
        }

        [Fact]
        [Trait("Category", "Golden")]
        public async Task Legacy_responses_match_the_golden_files()
        {
            _golden = GoldenRecorder.ForRepository();

            await Reads();
            await Writes();
            Exports();

            Assert.True(_golden.Mismatches.Count == 0, _golden.Report());
        }

        // ------------------------------------------------------------------ reads (seed data only)

        private async Task Reads()
        {
            await Get("suppliers-list", "api/suppliers");
            await Get("suppliers-47-accented-name", "api/suppliers/47");
            await Get("suppliers-999-not-found", "api/suppliers/999");
            await Get("suppliers-no-api-key", "api/suppliers", withKey: false);

            await Get("search-default", "api/purchase-orders");
            await Get("search-pending", "api/purchase-orders?status=Pending");
            await Get("search-text-urgent-case-insensitive", "api/purchase-orders?q=urgent");
            await Get("search-requiredby-asc-nulls-first", "api/purchase-orders?sort=RequiredBy&dir=asc");
            await Get("search-requiredby-desc", "api/purchase-orders?sort=RequiredBy&dir=desc");
            await Get("search-total-desc-page-3", "api/purchase-orders?sort=TotalAmount&dir=desc&page=3&pageSize=10");
            await Get("search-supplier-45", "api/purchase-orders?supplierId=45&sort=OrderNumber&dir=asc");
            await Get("search-date-range", "api/purchase-orders?from=2026-03-01&to=2026-03-08&sort=OrderDate&dir=asc");
            await Get("search-bad-sort", "api/purchase-orders?sort=Supplier");
            await Get("search-page-size-101", "api/purchase-orders?pageSize=101");
            await Get("search-bad-status", "api/purchase-orders?status=Cancelled");

            await Get("order-14-half-cent-line", "api/purchase-orders/14");
            await Get("order-125-datetime-997ms", "api/purchase-orders/125");
            await Get("order-250-datetime-003ms", "api/purchase-orders/250");
            await Get("order-1-uppercase-urgent-note", "api/purchase-orders/1");
            await Get("order-4-null-requiredby", "api/purchase-orders/4");
            await Get("order-9-rejected", "api/purchase-orders/9");
            await Get("order-49-accented-supplier", "api/purchase-orders/49");
            await Get("order-999999-not-found", "api/purchase-orders/999999");
        }

        // ------------------------------------------------------------------ writes (fresh database: next id 2001)

        private async Task Writes()
        {
            var created = await Post("write-01-create", "api/purchase-orders", Order(1,
                Line("SKU-GOLD-1", "Half-cent golden line", 1, 2.3450m, 0m),         // 2.345    -> 2.35
                Line("SKU-GOLD-2", "Discounted golden line", 3, 1.6750m, 12.5m)));  // 4.396875 -> 4.40
            var id = (int)created["Id"];
            var firstVersion = (string)created["Version"];

            var approved = await Post("write-02-approve", "api/purchase-orders/" + id + "/approve", Decision(firstVersion));
            await Post("write-03-approve-again-stale-version", "api/purchase-orders/" + id + "/approve", Decision(firstVersion));
            await Post("write-04-approve-again-current-version", "api/purchase-orders/" + id + "/approve",
                Decision((string)approved["Version"]));

            var big = await Post("write-05-create-over-limit", "api/purchase-orders", Order(1,
                Line("SKU-GOLD-3", "Bulk golden line", 200, 150m, 0m)));            // 30,000 > 25,000
            var bigId = (int)big["Id"];
            await Post("write-06-approve-over-limit", "api/purchase-orders/" + bigId + "/approve", Decision((string)big["Version"]));
            await Post("write-07-reject-over-limit", "api/purchase-orders/" + bigId + "/reject", Decision((string)big["Version"]));

            await Post("write-08-create-no-lines", "api/purchase-orders", Order(1));
            await Post("write-09-create-missing-supplier", "api/purchase-orders", Order(999, Line("SKU-GOLD-4", "Line", 1, 1m, 0m)));
            await Post("write-10-create-inactive-supplier", "api/purchase-orders", Order(2, Line("SKU-GOLD-4", "Line", 1, 1m, 0m)));
            await Post("write-11-create-line-without-sku", "api/purchase-orders", Order(1, Line(null, "Line", 1, 1m, 0m)));
            await Post("write-12-create-sku-41-chars", "api/purchase-orders", Order(1, Line(new string('X', 41), "Line", 1, 1m, 0m)));
            await Post("write-13-decision-without-version", "api/purchase-orders/" + id + "/reject", new { DecidedBy = "golden.approver" });

            // No idempotency: the same body twice makes two orders.
            var sameBody = Order(1, Line("SKU-GOLD-5", "Double-submitted line", 1, 10m, 0m));
            await Post("write-14-double-submit-first", "api/purchase-orders", sameBody);
            await Post("write-15-double-submit-second", "api/purchase-orders", sameBody);
        }

        // ------------------------------------------------------------------ the nightly export (en-US, like the server)

        private void Exports()
        {
            Export(new DateTime(2026, 5, 27));  // busiest approval day in the seed (10 orders)
            Export(new DateTime(2026, 1, 14));  // Mueller GmbH's first approval: one byte 0xFC per name
        }

        private void Export(DateTime day)
        {
            var folder = Path.Combine(Path.GetTempPath(), "purchasedesk-golden-export", Guid.NewGuid().ToString("N"));
            var previous = Thread.CurrentThread.CurrentCulture;
            Thread.CurrentThread.CurrentCulture = new CultureInfo("en-US");
            try
            {
                var result = new ExportRunner(Settings.Current.ConnectionString, folder).Run(day);
                _golden.RecordBytes("export/" + Path.GetFileName(result.Path), File.ReadAllBytes(result.Path));
            }
            finally
            {
                Thread.CurrentThread.CurrentCulture = previous;
            }
        }

        // ------------------------------------------------------------------ recording

        private Task<JToken> Get(string name, string path, bool withKey = true)
        {
            return Send(name, HttpMethod.Get, path, null, withKey, timesAreNow: false);
        }

        private Task<JToken> Post(string name, string path, object body)
        {
            return Send(name, HttpMethod.Post, path, body, withKey: true, timesAreNow: true);
        }

        // Sends one request, records request and response to golden/api/<name>.json, and returns the raw response
        // body (not normalised) so later scenarios can use its Id or Version.
        private async Task<JToken> Send(string name, HttpMethod method, string path, object body, bool withKey, bool timesAreNow)
        {
            var request = new HttpRequestMessage(method, path);
            if (body != null)
                request.Content = new StringContent(JsonConvert.SerializeObject(body), Encoding.UTF8, "application/json");

            HttpResponseMessage response;
            if (withKey)
            {
                response = await _api.Client.SendAsync(request);
            }
            else
            {
                using (var client = _api.ClientWithoutKey())
                    response = await client.SendAsync(request);
            }

            var raw = response.Content == null ? string.Empty : await response.Content.ReadAsStringAsync();
            var parsed = string.IsNullOrEmpty(raw) ? JValue.CreateNull() : GoldenRecorder.ParseExact(raw);

            var headers = new JObject();
            if (response.Content != null && response.Content.Headers.ContentType != null)
                headers["Content-Type"] = response.Content.Headers.ContentType.ToString();
            if (response.Headers.Location != null)
                headers["Location"] = response.Headers.Location.ToString();

            var requestRecord = new JObject { ["method"] = method.Method, ["path"] = "/" + path };
            if (body != null)
                requestRecord["body"] = GoldenRecorder.ParseExact(JsonConvert.SerializeObject(body));

            var document = new JObject
            {
                ["request"] = requestRecord,
                ["response"] = new JObject
                {
                    ["status"] = (int)response.StatusCode,
                    ["headers"] = headers,
                    ["body"] = GoldenRecorder.Normalize(parsed, timesAreNow),
                },
            };

            _golden.RecordText("api/" + name + ".json", GoldenRecorder.Pretty(document));
            return parsed;
        }

        private static object Order(int supplierId, params object[] lines)
        {
            return new { SupplierId = supplierId, CreatedBy = "golden.test", Notes = "Golden scenario", Lines = lines };
        }

        private static object Line(string sku, string description, int quantity, decimal unitPrice, decimal discountPercent)
        {
            return new { Sku = sku, Description = description, Quantity = quantity, UnitPrice = unitPrice, DiscountPercent = discountPercent };
        }

        private static object Decision(string version)
        {
            return new { DecidedBy = "golden.approver", Version = version };
        }
    }
}

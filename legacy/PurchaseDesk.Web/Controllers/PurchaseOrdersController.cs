using System;
using System.Linq;
using System.Web.Http;
using PurchaseDesk.Web.Data;
using PurchaseDesk.Web.Models;

namespace PurchaseDesk.Web.Controllers
{
    // The procedures enforce the business rules and raise 5000x errors; SqlErrorExceptionFilter maps them to HTTP.
    [RoutePrefix("api/purchase-orders")]
    public class PurchaseOrdersController : ApiController
    {
        [HttpGet, Route("")]
        public IHttpActionResult Search(
            int? supplierId = null, string status = null, DateTime? from = null, DateTime? to = null, string q = null,
            string sort = "OrderDate", string dir = "DESC", int page = 1, int pageSize = 25)
        {
            return Ok(PurchaseOrderData.Search(new SearchCriteria
            {
                SupplierId = supplierId,
                Status = status,
                From = from,
                To = to,
                Text = q,
                SortBy = sort,
                SortDir = dir,
                Page = page,
                PageSize = pageSize,
            }));
        }

        [HttpGet, Route("{id:int}", Name = "GetPurchaseOrder")]
        public IHttpActionResult Get(int id)
        {
            var order = PurchaseOrderData.Get(id);
            if (order == null)
                return NotFound();
            return Ok(order);
        }

        // No idempotency key: posting the same order twice creates two orders. A legacy trait.
        [HttpPost, Route("")]
        public IHttpActionResult Create([FromBody] CreatePurchaseOrderRequest request)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            if (request == null)
                return BadRequest("A request body is required.");
            if (request.Lines != null && request.Lines.Any(
                    l => l == null || string.IsNullOrWhiteSpace(l.Sku) || string.IsNullOrWhiteSpace(l.Description)))
                return BadRequest("Each line needs a Sku and a Description.");

            var id = PurchaseOrderData.Create(request);
            return CreatedAtRoute("GetPurchaseOrder", new { id }, PurchaseOrderData.Get(id));
        }

        [HttpPost, Route("{id:int}/approve")]
        public IHttpActionResult Approve(int id, [FromBody] DecisionRequest request)
        {
            return Decide(id, "Approved", request);
        }

        [HttpPost, Route("{id:int}/reject")]
        public IHttpActionResult Reject(int id, [FromBody] DecisionRequest request)
        {
            return Decide(id, "Rejected", request);
        }

        private IHttpActionResult Decide(int id, string newStatus, DecisionRequest request)
        {
            if (!ModelState.IsValid)
                return BadRequest(ModelState);
            if (request == null)
                return BadRequest("A request body is required.");
            if (request.Version == null || request.Version.Length != 8)
                return BadRequest("Version must be the Version from the purchase order you loaded.");

            PurchaseOrderData.SetStatus(id, newStatus, request.DecidedBy, Settings.Current.ApprovalLimit, request.Version);
            return Ok(PurchaseOrderData.Get(id));
        }
    }
}

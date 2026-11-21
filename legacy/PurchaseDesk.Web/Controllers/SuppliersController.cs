using System;
using System.Collections.Generic;
using System.Runtime.Caching;
using System.Web.Http;
using PurchaseDesk.Web.Data;
using PurchaseDesk.Web.Models;

namespace PurchaseDesk.Web.Controllers
{
    [RoutePrefix("api/suppliers")]
    public class SuppliersController : ApiController
    {
        private const string CacheKey = "suppliers:active";

        // Served from process memory for 10 minutes and never invalidated: a change to a supplier can take
        // 10 minutes to show, and two servers can disagree. A legacy trait the migration removes.
        [HttpGet, Route("")]
        public IHttpActionResult List()
        {
            var suppliers = MemoryCache.Default.Get(CacheKey) as IList<Supplier>;
            if (suppliers == null)
            {
                suppliers = SupplierData.ListActive();
                MemoryCache.Default.Set(CacheKey, suppliers, DateTimeOffset.UtcNow.AddMinutes(10));
            }
            return Ok(suppliers);
        }

        [HttpGet, Route("{id:int}")]
        public IHttpActionResult Get(int id)
        {
            var supplier = SupplierData.Get(id);
            if (supplier == null)
                return NotFound();
            return Ok(supplier);
        }
    }
}

using System;
using System.Collections.Generic;

namespace PurchaseDesk.Web.Models
{
    public class PurchaseOrderSummary
    {
        public int Id { get; set; }
        public string OrderNumber { get; set; }
        public int SupplierId { get; set; }
        public string SupplierName { get; set; }
        public string Status { get; set; }
        public DateTime OrderDate { get; set; }
        public DateTime? RequiredBy { get; set; }  // a date column; Newtonsoft writes it as 2026-02-01T00:00:00
        public decimal TotalAmount { get; set; }  // money: comes back with four decimals, e.g. 150.1500
        public int LineCount { get; set; }
    }

    public class SearchResult
    {
        public int TotalCount { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
        public IList<PurchaseOrderSummary> Items { get; set; }
    }

    public class PurchaseOrder
    {
        public int Id { get; set; }
        public string OrderNumber { get; set; }
        public int SupplierId { get; set; }
        public string SupplierCode { get; set; }
        public string SupplierName { get; set; }
        public string Status { get; set; }
        public DateTime OrderDate { get; set; }
        public DateTime? RequiredBy { get; set; }
        public string Notes { get; set; }
        public decimal TotalAmount { get; set; }
        public string CreatedBy { get; set; }
        public string DecidedBy { get; set; }
        public DateTime? DecidedAt { get; set; }
        public byte[] Version { get; set; }  // the rowversion; Newtonsoft writes it as base64
        public IList<PurchaseOrderLine> Lines { get; set; }
    }

    public class PurchaseOrderLine
    {
        public int LineNumber { get; set; }
        public string Sku { get; set; }
        public string Description { get; set; }
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal DiscountPercent { get; set; }
        public decimal LineAmount { get; set; }
    }

    public class CreatePurchaseOrderRequest
    {
        public int SupplierId { get; set; }
        public DateTime? RequiredBy { get; set; }
        public string Notes { get; set; }
        public string CreatedBy { get; set; }  // trusted as sent: there is no real identity in the legacy app
        public IList<CreatePurchaseOrderLine> Lines { get; set; }
    }

    public class CreatePurchaseOrderLine
    {
        public string Sku { get; set; }
        public string Description { get; set; }
        public int Quantity { get; set; }
        public decimal UnitPrice { get; set; }
        public decimal DiscountPercent { get; set; }
    }

    public class DecisionRequest
    {
        public string DecidedBy { get; set; }  // trusted as sent
        public byte[] Version { get; set; }    // the Version from the last GET
    }
}

using System;

namespace PurchaseDesk.Web.Models
{
    // Separate classes rather than inheritance: Newtonsoft orders inherited properties after declared ones,
    // and the JSON field order is part of what the golden files record.
    public class Supplier
    {
        public int Id { get; set; }
        public string Code { get; set; }
        public string Name { get; set; }
        public string Email { get; set; }
        public bool IsActive { get; set; }
    }

    public class SupplierDetail
    {
        public int Id { get; set; }
        public string Code { get; set; }
        public string Name { get; set; }
        public string Email { get; set; }
        public bool IsActive { get; set; }
        public DateTime CreatedAt { get; set; }
    }
}

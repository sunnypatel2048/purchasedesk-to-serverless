using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using PurchaseDesk.Web.Models;

namespace PurchaseDesk.Web.Data
{
    internal class SearchCriteria
    {
        public int? SupplierId { get; set; }
        public string Status { get; set; }
        public DateTime? From { get; set; }
        public DateTime? To { get; set; }
        public string Text { get; set; }
        public string SortBy { get; set; }
        public string SortDir { get; set; }
        public int Page { get; set; }
        public int PageSize { get; set; }
    }

    internal static class PurchaseOrderData
    {
        public static SearchResult Search(SearchCriteria c)
        {
            var items = new List<PurchaseOrderSummary>();
            using (var connection = Db.Open())
            using (var command = Db.Procedure(connection, "dbo.usp_SearchPurchaseOrders"))
            {
                command.Parameters.Add("@SupplierId", SqlDbType.Int).Value = Db.OrDbNull(c.SupplierId);
                command.Parameters.Add("@Status", SqlDbType.VarChar, 10).Value = Db.OrDbNull(c.Status);
                command.Parameters.Add("@FromDate", SqlDbType.DateTime).Value = Db.OrDbNull(c.From);
                command.Parameters.Add("@ToDate", SqlDbType.DateTime).Value = Db.OrDbNull(c.To);
                command.Parameters.Add("@Text", SqlDbType.NVarChar, 100).Value = Db.OrDbNull(c.Text);
                command.Parameters.Add("@SortBy", SqlDbType.VarChar, 20).Value = Db.OrDbNull(c.SortBy);
                command.Parameters.Add("@SortDir", SqlDbType.VarChar, 4).Value = Db.OrDbNull(c.SortDir);
                command.Parameters.Add("@Page", SqlDbType.Int).Value = c.Page;
                command.Parameters.Add("@PageSize", SqlDbType.Int).Value = c.PageSize;
                var total = command.Parameters.Add("@TotalCount", SqlDbType.Int);
                total.Direction = ParameterDirection.Output;

                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        items.Add(new PurchaseOrderSummary
                        {
                            Id = reader.Int("Id"),
                            OrderNumber = reader.StringOrNull("OrderNumber"),
                            SupplierId = reader.Int("SupplierId"),
                            SupplierName = reader.StringOrNull("SupplierName"),
                            Status = reader.StringOrNull("Status"),
                            OrderDate = reader.DateTime("OrderDate"),
                            RequiredBy = reader.DateTimeOrNull("RequiredBy"),
                            TotalAmount = reader.Decimal("TotalAmount"),
                            LineCount = reader.Int("LineCount"),
                        });
                    }
                }

                // Output parameters are only populated once the reader is closed.
                return new SearchResult
                {
                    TotalCount = (int)total.Value,
                    Page = c.Page,
                    PageSize = c.PageSize,
                    Items = items,
                };
            }
        }

        public static PurchaseOrder Get(int id)
        {
            using (var connection = Db.Open())
            using (var command = Db.Procedure(connection, "dbo.usp_GetPurchaseOrder"))
            {
                command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
                using (var reader = command.ExecuteReader())
                {
                    if (!reader.Read())
                        return null;

                    var order = new PurchaseOrder
                    {
                        Id = reader.Int("Id"),
                        OrderNumber = reader.StringOrNull("OrderNumber"),
                        SupplierId = reader.Int("SupplierId"),
                        SupplierCode = reader.StringOrNull("SupplierCode"),
                        SupplierName = reader.StringOrNull("SupplierName"),
                        Status = reader.StringOrNull("Status"),
                        OrderDate = reader.DateTime("OrderDate"),
                        RequiredBy = reader.DateTimeOrNull("RequiredBy"),
                        Notes = reader.StringOrNull("Notes"),
                        TotalAmount = reader.Decimal("TotalAmount"),
                        CreatedBy = reader.StringOrNull("CreatedBy"),
                        DecidedBy = reader.StringOrNull("DecidedBy"),
                        DecidedAt = reader.DateTimeOrNull("DecidedAt"),
                        Version = reader.Bytes("RowVer"),
                        Lines = new List<PurchaseOrderLine>(),
                    };

                    reader.NextResult();
                    while (reader.Read())
                    {
                        order.Lines.Add(new PurchaseOrderLine
                        {
                            LineNumber = reader.Short("LineNumber"),
                            Sku = reader.StringOrNull("Sku"),
                            Description = reader.StringOrNull("Description"),
                            Quantity = reader.Int("Quantity"),
                            UnitPrice = reader.Decimal("UnitPrice"),
                            DiscountPercent = reader.Decimal("DiscountPercent"),
                            LineAmount = reader.Decimal("LineAmount"),
                        });
                    }
                    return order;
                }
            }
        }

        // Returns the new order's id. The lines go in as a table-valued parameter, numbered in the order sent.
        public static int Create(CreatePurchaseOrderRequest request)
        {
            var lines = new DataTable();
            lines.Columns.Add("LineNumber", typeof(short));
            lines.Columns.Add("Sku", typeof(string));
            lines.Columns.Add("Description", typeof(string));
            lines.Columns.Add("Quantity", typeof(int));
            lines.Columns.Add("UnitPrice", typeof(decimal));
            lines.Columns.Add("DiscountPercent", typeof(decimal));

            short number = 0;
            foreach (var line in request.Lines ?? new List<CreatePurchaseOrderLine>())
            {
                number++;
                lines.Rows.Add(number, line.Sku, line.Description, line.Quantity, line.UnitPrice, line.DiscountPercent);
            }

            using (var connection = Db.Open())
            using (var command = Db.Procedure(connection, "dbo.usp_CreatePurchaseOrder"))
            {
                command.Parameters.Add("@SupplierId", SqlDbType.Int).Value = request.SupplierId;
                command.Parameters.Add("@RequiredBy", SqlDbType.Date).Value = Db.OrDbNull(request.RequiredBy);
                command.Parameters.Add("@Notes", SqlDbType.NVarChar, 500).Value = Db.OrDbNull(request.Notes);
                command.Parameters.Add("@CreatedBy", SqlDbType.NVarChar, 100).Value = Db.OrDbNull(request.CreatedBy);
                var tvp = command.Parameters.Add("@Lines", SqlDbType.Structured);
                tvp.TypeName = "dbo.PurchaseOrderLineInput";
                tvp.Value = lines;

                using (var reader = command.ExecuteReader())
                {
                    reader.Read();
                    return reader.Int("Id");
                }
            }
        }

        public static void SetStatus(int id, string newStatus, string decidedBy, decimal approvalLimit, byte[] version)
        {
            using (var connection = Db.Open())
            using (var command = Db.Procedure(connection, "dbo.usp_SetPurchaseOrderStatus"))
            {
                command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
                command.Parameters.Add("@NewStatus", SqlDbType.VarChar, 10).Value = newStatus;
                command.Parameters.Add("@DecidedBy", SqlDbType.NVarChar, 100).Value = Db.OrDbNull(decidedBy);
                command.Parameters.Add("@ApprovalLimit", SqlDbType.Money).Value = approvalLimit;
                command.Parameters.Add("@RowVer", SqlDbType.Binary, 8).Value = version;
                command.ExecuteNonQuery();
            }
        }
    }
}

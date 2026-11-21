using System.Collections.Generic;
using System.Data;
using PurchaseDesk.Web.Models;

namespace PurchaseDesk.Web.Data
{
    internal static class SupplierData
    {
        public static IList<Supplier> ListActive()
        {
            var suppliers = new List<Supplier>();
            using (var connection = Db.Open())
            using (var command = Db.Procedure(connection, "dbo.usp_ListSuppliers"))
            {
                command.Parameters.Add("@IncludeInactive", SqlDbType.Bit).Value = false;
                using (var reader = command.ExecuteReader())
                {
                    while (reader.Read())
                    {
                        suppliers.Add(new Supplier
                        {
                            Id = reader.Int("Id"),
                            Code = reader.StringOrNull("Code"),
                            Name = reader.StringOrNull("Name"),
                            Email = reader.StringOrNull("Email"),
                            IsActive = reader.Bool("IsActive"),
                        });
                    }
                }
            }
            return suppliers;
        }

        public static SupplierDetail Get(int id)
        {
            using (var connection = Db.Open())
            using (var command = Db.Procedure(connection, "dbo.usp_GetSupplier"))
            {
                command.Parameters.Add("@Id", SqlDbType.Int).Value = id;
                using (var reader = command.ExecuteReader())
                {
                    if (!reader.Read())
                        return null;

                    return new SupplierDetail
                    {
                        Id = reader.Int("Id"),
                        Code = reader.StringOrNull("Code"),
                        Name = reader.StringOrNull("Name"),
                        Email = reader.StringOrNull("Email"),
                        IsActive = reader.Bool("IsActive"),
                        CreatedAt = reader.DateTime("CreatedAt"),
                    };
                }
            }
        }
    }
}

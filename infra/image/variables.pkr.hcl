variable "region" {
  type    = string
  default = "us-east-1"
}

variable "instance_type" {
  description = "Build instance. 8 GB of memory keeps SQL Server setup quick; only runs during a build."
  type        = string
  default     = "t3.large"
}

# SQL Server 2019 CU32 + GDR security update, KB5132745 (November 10, 2026). Applied in the same setup run as the
# RTM media. Microsoft's prerequisite: "SQL Server 2019 or any SQL Server 2019 CU release".
# URL: the Microsoft Update Catalog's direct link for "Security Update for SQL Server 2019 RTM CU (KB5132745)".
# SHA-256: the "File hash information" table on Microsoft's KB5132745 page. The build refuses any other file.
variable "sql_update_url" {
  type    = string
  default = "https://catalog.s.download.windowsupdate.com/c/msdownload/update/software/secu/2026/11/sqlserver2019-kb5132745-x64_f5eed5128f42b88ade343119992c2f5cddc533c8.exe"
}

variable "sql_update_sha256" {
  type    = string
  default = "98B54010BF5C4AE694DAEC974CEB4A02AC806889E1AF88DBD1014A1622C2B0E2"
}

variable "sql_build" {
  description = "The build the verify step requires: SERVERPROPERTY('ProductVersion') after the update."
  type        = string
  default     = "15.0.4510.2"
}

variable "git_commit" {
  description = "Recorded as a tag on the image. `make image` passes the current commit."
  type        = string
  default     = "unknown"
}

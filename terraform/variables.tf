variable "provider_sp" {
  type = object({
    subscription_id = string
    tenant_id       = string
    client_id       = string
    client_secret   = string
  })
  default = {
    subscription_id = ""
    tenant_id       = ""
    client_id       = ""
    client_secret   = ""
  }
}

variable "rg_name" {
  type        = string
  default     = "aliyun-test"
  description = "Name of the resources group"
}

variable "location" {
  type        = string
  default     = "uksouth"
  description = "Region where resources will be deployed"
}

variable "cluster_name" {
  type        = string
  default     = "aliyun-aks"
  description = "Name of the cluster"
}

variable "workers_type" {
  type        = string
  default     = "Standard_NC4as_T4_v3"
  description = "Type of GPU workers to be included"
}

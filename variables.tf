##
## variables.tf
##

##
## Declare variables so we can use them.
##

##
## Capstone group infrastructure alias
##
variable "group_alias" {
  type        = string
  description = "Capstone group alias"
}

##
## Capstone group infrastructure alias
##
variable "account_id" {
  type        = string
  description = "Class account id"
}

##
## Capstone group infrastructure alias
##
variable "region" {
  type        = string
  description = "Default AWS Region"
}

##
## Todo application source data file name
##
variable "todo_source_file" {
  type        = string
  description = "Todo application source file name"
}


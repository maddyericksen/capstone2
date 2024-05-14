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
## Todo application source data file name
##
variable "todo_source_file" {
  type        = string
  description = "Todo application source file name"
}


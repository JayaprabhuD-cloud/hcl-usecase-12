package main

deny[msg] {
  resource := input.resource_changes[_]
  resource.type == "aws_instance"

  not resource.change.after.tags["Name"]
  msg = sprintf("Missing 'Name' tag for resource: %s", [resource.address])
}
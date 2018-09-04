# Region WAF with ALB

This example shows how to configure AWS waf for an ALB Endpoint. It is based on ECS-ELB example. 


To run, configure your AWS provider as described in https://www.terraform.io/docs/providers/aws/index.html

## Get up and running

Planning phase

```
tf plan -var="ssh_keyname={your_key_name}"
```

Apply phase

```
tf apply -var="ssh_keyname={your_key_name}"
```

Once the stack is created, wait for a few minutes and test the stack by launching a browser with the ALB url.

## Destroy :boom:

```
tf destroy -var="ssh_keyname={your_key_name"

```

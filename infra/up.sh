#!/bin/bash

go env -w CGO_ENABLED=1                                                                             
go env -w CC=musl-gcc                                                                               
go build -ldflags '-linkmode external -extldflags "-static -Wl,-unresolved-symbols=ignore-all"' -o bin/sourdough-go-web-k8s-infra .
                                                                                                    
pulumi up         

FROM alpine:3.12.3 as builder

RUN apk --no-cache --no-progress add git ca-certificates tzdata make \
    && update-ca-certificates \
    && rm -rf /var/cache/apk/*

# Create a minimal container to run a Golang static binary
FROM scratch

COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

# Copy the application binary - make sure it is the same name as defined in the Makefile
COPY out/myapp-linux-amd64 /myapp

ENTRYPOINT ["/myapp"]
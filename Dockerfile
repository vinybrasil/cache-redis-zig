# Use Alpine Linux as the base image
FROM alpine:latest AS builder

# Install dependencies
RUN apk add --no-cache \
    build-base \
    curl \
    tar \
    xz

# Download and install Zig
ARG ZIG_VERSION=0.14.0
RUN curl -L https://ziglang.org/download/${ZIG_VERSION}/zig-linux-x86_64-${ZIG_VERSION}.tar.xz -o zig.tar.xz && \
    tar -xf zig.tar.xz && \
    mv zig-linux-x86_64-${ZIG_VERSION} /zig && \
    rm zig.tar.xz

# Add Zig to PATH
ENV PATH="/zig:${PATH}"

# Set the working directory
WORKDIR /app

# Copy the source code into the container
COPY . .

# Build the application
RUN zig build -Doptimize=ReleaseSafe

# Use a minimal Alpine image for the final container
FROM alpine:latest

# Copy the built binary from the builder stage
COPY --from=builder /app/zig-out/bin/zap_redis /usr/local/bin/zap_redis

# Expose the port your app listens on (e.g., 3000 for Zap)
EXPOSE 3000

# Run the application
CMD ["zap_redis"]
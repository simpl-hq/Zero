# syntax=docker/dockerfile:1.7.0-labs
ARG DISTRO=ubuntu
ARG TAG=24.04

FROM ${DISTRO}:${TAG} AS build

### Build stage

# Install curl and git and zeroq dependencies
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y ca-certificates curl git build-essential libgmp-dev zlib1g-dev llvm llvm-dev libnuma-dev libssl-dev && \
    rm -rf /var/lib/apt/lists/*

# Specify bootstrap Haskell versions
ENV BOOTSTRAP_HASKELL_GHC_VERSION=9.6.3
ENV BOOTSTRAP_HASKELL_CABAL_VERSION=3.12.1.0

# Do not install Stack
ENV BOOTSTRAP_HASKELL_INSTALL_NO_STACK=true
ENV BOOTSTRAP_HASKELL_INSTALL_NO_STACK_HOOK=true

# Install ghcup
RUN curl --proto '=https' --tlsv1.2 -sSf https://get-ghcup.haskell.org | BOOTSTRAP_HASKELL_NONINTERACTIVE=1 sh

# Adjust PATH
ENV PATH="/root/.cabal/bin:/root/.ghcup/bin:$PATH"

# Set both as default
RUN ghcup set ghc "${BOOTSTRAP_HASKELL_GHC_VERSION}" && \
    ghcup set cabal "${BOOTSTRAP_HASKELL_CABAL_VERSION}" && \
    sed -i 's/-fuse-ld=gold//g' "$(ghc --print-libdir)/settings"

# Copy only the source code
COPY apps /project/apps/
COPY cbits /project/cbits/
COPY src /project/src/

COPY cabal.project Setup.hs zeroq.cabal LICENSE /project

WORKDIR /project

# Debug
#ARG CACHEBUST=1

#ADD --chmod=755 https://github.com/MShekow/directory-checksum/releases/download/v1.4.6/directory-checksum_1.4.6_linux_amd64 /usr/local/bin/directory-checksum
#RUN directory-checksum --max-depth 2 .

# Set build arguments and check if they exist
ARG APP
RUN if [ -z "$APP" ]; then printf "Please specify \$APP build-arg.\n"; exit 1; fi

# Compile app
RUN cabal update
RUN cabal build exe:$APP

# Copy scripts
COPY scripts /project/scripts/

# Create new path containing all files needed
RUN mkdir /final
WORKDIR /final

# Strip the binary from debug symbols to reduce size
RUN bin="$(find /project/dist-newstyle -name "$APP" -type f -executable)" && \
    mv "$bin" ./ && \
    strip ./"$APP" &&\
    mv /project/scripts/docker/entrypoint-"$APP" ./entrypoint &&\
    mv /project/scripts/main/zero-servers-stopscript ./zero-servers-stopscript

### Final stage
FROM ${DISTRO}:${TAG}

# Install runtime OpenSSL, CA certificates, and NUMA/GMP/zlib dependencies
RUN DEBIAN_FRONTEND=noninteractive apt-get update && \
    apt-get install -y ca-certificates openssl libnuma1 libgmp10 zlib1g && \
    (apt-get install -y libssl3t64 || apt-get install -y libssl3) && \
    rm -rf /var/lib/apt/lists/*

# Copy compiled app from build stage
COPY --from=build /final /usr/local/bin/

# Open app listening port
ARG APP_PORT
RUN if [ -z "$APP_PORT" ]; then printf "Please specify \$APP_PORT build-arg.\n"; exit 1; fi

EXPOSE $APP_PORT

# zeroq requires using SIGINT to correctly preserve undelivered messages and restore them on restart
STOPSIGNAL SIGINT

# Finally, execute helper script
ENTRYPOINT [ "/usr/local/bin/entrypoint" ]

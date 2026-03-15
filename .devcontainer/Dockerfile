FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Etc/UTC

# gem5 build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    git \
    scons \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-pydot \
    python3-six \
    libprotobuf-dev \
    protobuf-compiler \
    libgoogle-perftools-dev \
    libboost-all-dev \
    libhdf5-dev \
    libpng-dev \
    zlib1g-dev \
    m4 \
    pkg-config \
    wget \
    curl \
    vim \
    gdb \
    valgrind \
    && rm -rf /var/lib/apt/lists/*

# Clone gem5 (stable branch)
WORKDIR /opt
RUN git clone https://gem5.googlesource.com/public/gem5 --depth 1 -b stable

WORKDIR /opt/gem5

# Build gem5 for x86 SE mode
# Uses 12 threads — adjust -j if want to limit during container build
# NOTE: This step takes 20-40 min. Comment it out if prefer to build manually.
RUN scons build/X86/gem5.opt -j$(nproc)

# Add gem5 binary to PATH
ENV PATH="/opt/gem5/build/X86:${PATH}"

WORKDIR /workspace

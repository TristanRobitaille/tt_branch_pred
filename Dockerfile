FROM ubuntu:22.04
LABEL description="TinyTapeout Branch Predictor Docker Image"

#----- Packages -----#
RUN apt-get update && apt-get install -y \
    autoconf \
    automake \
    autotools-dev \
    curl \
    python3 \
    python3-pip \
    python3-tomli \
    libmpc-dev \
    libmpfr-dev \
    libgmp-dev \
    gawk \
    build-essential \
    bison \
    flex \
    texinfo \
    gperf \
    libtool \
    patchutils \
    bc \
    zlib1g-dev \
    libexpat-dev \
    ninja-build \
    git \
    cmake \
    libglib2.0-dev \
    libslirp-dev && \
    rm -rf /var/lib/apt/lists/*

#----- Build RISC-V toolchain -----#
RUN git clone --recursive https://github.com/riscv-collab/riscv-gnu-toolchain.git

RUN cd riscv-gnu-toolchain && \
    ./configure --prefix=/opt/riscv --with-arch=rv32i --with-abi=ilp32 && \
    make -j20

RUN echo 'export PATH=/opt/riscv/bin:$PATH' >> ~/.bashrc && \
    echo 'export LD_LIBRARY_PATH=/opt/riscv/lib:$LD_LIBRARY_PATH' >> ~/.bashrc && \
    . ~/.bashrc

# Clean up
WORKDIR /tmp
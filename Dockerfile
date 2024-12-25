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
    libslirp-dev \
    device-tree-compiler \
    iverilog && \
    rm -rf /var/lib/apt/lists/*

#----- Build RISC-V toolchain -----#
RUN git clone --recursive https://github.com/riscv-collab/riscv-gnu-toolchain.git

# Compiler
RUN cd riscv-gnu-toolchain && \
    ./configure --prefix=/opt/riscv --with-arch=rv32i_zicsr_zifencei --with-abi=ilp32 && \
    make -j10

RUN echo 'export PATH=/opt/riscv/bin:$PATH' >> ~/.bashrc && \
    echo 'export LD_LIBRARY_PATH=/opt/riscv/lib:$LD_LIBRARY_PATH' >> ~/.bashrc && \
    . ~/.bashrc

# Simulator
RUN git clone https://github.com/riscv/riscv-isa-sim.git && \
    cd riscv-isa-sim && \
    mkdir build && \
    cd build && \
    ../configure --prefix=/opt/riscv_sim && \
    make -j10 && \
    make -j10 install

RUN echo 'export PATH=/opt/riscv_sim/bin:$PATH' >> ~/.bashrc && \
    . ~/.bashrc

# Proxy Kernel
RUN git clone https://github.com/riscv-software-src/riscv-pk.git && \
    cd riscv-pk && \
    mkdir build && \
    cd build && \
    ../configure --host=riscv32-unknown-elf --prefix=/opt/riscv_pk/riscv32-unknown-elf && \
    make -j10 && \
    make -j10 install

RUN echo 'export PATH=/opt/riscv_pk/riscv32-unknown-elf/riscv32-unknown-elf/bin:$PATH' >> ~/.bashrc && \
    . ~/.bashrc

#----- Python -----#
COPY test/requirements.txt .
RUN pip3 install --upgrade -r requirements.txt
RUN rm requirements.txt

# Clean up
WORKDIR /tmp
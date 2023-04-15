# Get the CUDA toolkit from the NVIDIA CUDA image
FROM docker.io/nvidia/cuda:${CUDA_VERSION}-devel-rockylinux${RHEL_VERSION} as cuda-builder

# Use the official Rocky Linux image
FROM rockylinux:${RHEL_VERSION}-minimal

ARG USER_ID
ARG GROUP_ID
ARG USERNAME
ARG GROUPNAME
ARG CORES
ARG RHEL_VERSION
ARG CUDA_VERSION
ARG ARCHITECTURE
ARG USE_GPU_AWARE_MPI
ARG USE_GPU_P2P
ARG TARGET

# This code is just ensuring that our user exists and is running with the same permissions as the host user.
# This is usually userid/gid 1000
RUN echo "GROUP_ID=${GROUP_ID} GROUPNAME=${GROUPNAME}"
RUN echo "RHEL_VERSION=${RHEL_VERSION}"
RUN (getent group ${GROUP_ID}  && (echo groupdel by-id ${GROUP_ID}; groupdel $(getent group ${GROUP_ID} | cut -d: -f1))) ||:
RUN (getent group ${GROUPNAME} && (echo groupdel ${GROUPNAME}; groupdel ${GROUPNAME})) ||:
RUN (getent passwd ${USERNAME} && (echo userdel ${USERNAME}; userdel -f ${USERNAME})) ||:
RUN groupadd -g ${GROUP_ID} ${GROUPNAME}
RUN useradd -l -u ${USER_ID} -g ${GROUPNAME} ${USERNAME}

RUN microdnf update -y
RUN microdnf install -y cmake
RUN microdnf install -y gcc-c++
RUN microdnf install -y openmpi-devel
RUN microdnf install -y kernel-devel
RUN microdnf install -y openmpi

# Set environment variables for CUDA
ENV PATH=/usr/lib64/openmpi/bin:$PATH
ENV PATH=/usr/local/cuda/bin:$PATH
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"

# Set the environment variables in the user's shell profile
RUN echo 'export PATH="/usr/lib64/openmpi/bin:$PATH"' >> /home/${USERNAME}/.profile
RUN echo 'export PATH="/usr/local/cuda/bin/nvcc:${PATH}"' >> /home/${USERNAME}/.profile
RUN echo 'export LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"' >> /home/${USERNAME}/.profile

# Create simulateqcd directory
RUN mkdir /simulateqcd
RUN mkdir /build

# Copy source code into the container
COPY src /simulateqcd/src
COPY CMakeLists.txt /simulateqcd/CMakeLists.txt
COPY parameter /simulateqcd/parameter
COPY scripts /simulateqcd/scripts
COPY test_conf /simulateqcd/test_conf

# Copy CUDA Toolkit from the CUDA builder image. We put this later on because the copy is
# sufficiently large that podman can't cache it so anything after this must rerun every time.
COPY --from=cuda-builder /usr/local/cuda /usr/local/cuda

# Set the working directory to /app
WORKDIR /build

# Test CUDA installation
RUN nvcc --version

# Build code using cmake
RUN cmake ../simulateqcd/ -DARCHITECTURE=${ARCHITECTURE} -DUSE_GPU_AWARE_MPI=${USE_GPU_AWARE_MPI} -DUSE_GPU_P2P=${USE_GPU_P2P}
RUN make -j ${CORES} ${TARGET}

# Set the user to the user we created earlier
USER ${USERNAME}
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USERNAME=simulateqcd
ARG GROUPNAME=simulateqcd
ARG CMD

# Use an official Rocky Linux 9 image
FROM rockylinux:9-minimal

ARG USER_ID
ARG GROUP_ID
ARG USERNAME
ARG GROUPNAME
ARG CMD

# Install necessary dependencies
RUN microdnf update -y
RUN microdnf install -y cmake
RUN microdnf install -y gcc-c++
RUN microdnf install -y openmpi
RUN microdnf install -y kernel-devel

# Add NVIDIA repository and install the CUDA Toolkit
RUN curl -sSL https://developer.download.nvidia.com/compute/cuda/repos/rhel9/x86_64/cuda-rhel9.repo > /etc/yum.repos.d/cuda.repo
RUN microdnf install -y cuda

# Set environment variables for CUDA
# TODO: This probably needs to be permanent
ENV PATH="/usr/local/cuda/bin:${PATH}"
ENV LD_LIBRARY_PATH="/usr/local/cuda/lib64:${LD_LIBRARY_PATH}"

# Test CUDA installation
RUN nvcc --version

# Set environment variables (if needed) TODO - remove
# ENV MY_VAR=myvalue

RUN mkdir /build

# Copy source code into the container
COPY ../src /build

# Set the working directory to /app
WORKDIR /build

# Build code using cmake
# TODO - Need to parameterize these options
RUN cmake /build/ -DARCHITECTURE="70" -DUSE_GPU_AWARE_MPI=ON -DUSE_GPU_P2P=ON
RUN make -j 4 

# This code is just ensuring that our user exists and is running with the same permissions as the host user.
# This is usually userid/gid 1000
RUN (getent group ${GROUP_ID}  && (echo groupdel by-id ${GROUP_ID}; groupdel $(getent group ${GROUP_ID} | cut -d: -f1))) ||:
RUN (getent group ${GROUPNAME} && (echo groupdel ${GROUPNAME}; groupdel ${GROUPNAME})) ||:
RUN (getent passwd ${USERNAME} && (echo userdel ${USERNAME}; userdel -f ${USERNAME})) ||:
RUN groupadd -g ${GROUP_ID} ${GROUPNAME}
RUN useradd -l -u ${USER_ID} -g ${GROUPNAME} ${USERNAME}

# Set the user for the build. Note: Keep in mind that during the build, the user
# runs with root privileges.
USER ${USERNAME}
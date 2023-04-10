
# Build the CUDA toolkit. We do this because the size of the CUDA toolkit
# exceeds that of the Docker build cache. This means if you want to make any
# changes to the CUDA toolkit, you need to rebuild the entire image including
# redownloading the entire 8 GBs. Using it as a builder bypasses this problem.
#FROM rockylinux:${RHEL_VERSION}-minimal as cuda-builder
FROM docker.io/nvidia/cuda:${CUDA_VERSION}-devel-rockylinux${RHEL_VERSION} as cuda-builder

# Add NVIDIA repository and install the CUDA Toolkit
#RUN curl -sSL "https://developer.download.nvidia.com/compute/cuda/repos/rhel${RHEL_VERSION}/x86_64/cuda-rhel${RHEL_VERSION}.repo" > /etc/yum.repos.d/cuda.repo
#RUN microdnf install -y cuda

# Use the official Rocky Linux image
FROM rockylinux:${RHEL_VERSION}-minimal

# Copy CUDA from the CUDA builder. Keep in mind that due to the size of these
# files there is a large chance that everything after this line will rerun
# after each build.
COPY --from=cuda-builder /usr/local/cuda-12.1 /usr/local/cuda-12.1

RUN microdnf update -y
RUN microdnf install -y cmake
RUN microdnf install -y gcc-c++
RUN microdnf install -y openmpi-devel
RUN microdnf install -y kernel-devel
RUN microdnf install -y openmpi

ARG USER_ID
ARG GROUP_ID
ARG USERNAME
ARG GROUPNAME
ARG CORES

# This code is just ensuring that our user exists and is running with the same permissions as the host user.
# This is usually userid/gid 1000
RUN (getent group ${GROUP_ID}  && (echo groupdel by-id ${GROUP_ID}; groupdel $(getent group ${GROUP_ID} | cut -d: -f1))) ||:
RUN (getent group ${GROUPNAME} && (echo groupdel ${GROUPNAME}; groupdel ${GROUPNAME})) ||:
RUN (getent passwd ${USERNAME} && (echo userdel ${USERNAME}; userdel -f ${USERNAME})) ||:
RUN groupadd -g ${GROUP_ID} ${GROUPNAME}
RUN useradd -l -u ${USER_ID} -g ${GROUPNAME} ${USERNAME}

# Set environment variables for CUDA
# TODO: This probably needs to be permanent
ENV PATH=/usr/lib64/openmpi/bin:$PATH
ENV PATH=/usr/local/cuda-12.1/bin:$PATH
ENV LD_LIBRARY_PATH="/usr/local/cuda-12.1/lib64:${LD_LIBRARY_PATH}"

# Set the environment variables in the user's shell profile
RUN echo 'export PATH="/usr/lib64/openmpi/bin:$PATH"' >> /home/${USERNAME}/.profile
RUN echo 'export PATH="/usr/local/cuda-12.1/bin/nvcc:${PATH}"' >> /home/${USERNAME}/.profile
RUN echo 'export LD_LIBRARY_PATH="/usr/local/cuda-12.1/lib64:${LD_LIBRARY_PATH}"' >> /home/${USERNAME}/.profile

# Create simulateqcd directory
RUN mkdir /simulateqcd
RUN mkdir /build

# Copy source code into the container
COPY ../src /simulateqcd/src
COPY ../CMakeLists.txt /simulateqcd/CMakeLists.txt
COPY ../parameter /simulateqcd/parameter
COPY ../scripts /simulateqcd/scripts
COPY ../test_conf /simulateqcd/test_conf

# Set the working directory to /app
WORKDIR /build

# Test CUDA installation
RUN nvcc --version

# Build code using cmake
# TODO - Need to parameterize these options
RUN cmake ../simulateqcd/ -DARCHITECTURE="70" -DUSE_GPU_AWARE_MPI=ON -DUSE_GPU_P2P=ON -DMPI_CXX_LIBRARIES=/usr/lib64/openmpi/lib/libmpi_cxx.so -DMPI_CXX_HEADER_DIR=/usr/include/openmpi-x86_64  -DCMAKE_CUDA_COMPILER=/usr/local/cuda-12.1/bin/nvcc
RUN make -j ${CORES}

# Set the user to the user we created earlier
USER ${USERNAME}
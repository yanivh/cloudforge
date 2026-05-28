FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV PYTHONUNBUFFERED=1
ENV PATH="/usr/local/bin:$PATH"

# Base system packages + deadsnakes PPA for Python 3.11
RUN apt-get update && apt-get install -y \
    software-properties-common \
    curl wget git vim build-essential cmake ninja-build \
    gdal-bin libgdal-dev libgl1 libglib2.0-0 \
    openssh-client ca-certificates \
    && add-apt-repository ppa:deadsnakes/ppa \
    && apt-get update \
    && apt-get install -y \
    python3.11 python3.11-dev python3.11-venv python3.11-distutils \
    && rm -rf /var/lib/apt/lists/*

# Make python3.11 the system default
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.11 1 \
    && update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.11 1

# pip
RUN curl -sS https://bootstrap.pypa.io/get-pip.py | python3.11

# Node.js 20 (required by Claude Code)
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI — pin to a specific version for reproducibility
# To upgrade: change CLAUDE_CODE_VERSION and rebuild
ARG CLAUDE_CODE_VERSION=1
RUN npm install -g @anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}

WORKDIR /data/projects

# Port for web app development (flask, fastapi, etc.)
EXPOSE 8080

CMD ["sleep", "infinity"]

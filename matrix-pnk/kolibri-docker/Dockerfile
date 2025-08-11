FROM python:3.11-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV KOLIBRI_HOME=/kolibri_home
ENV PATH=/opt/venv/bin:$PATH

# Create kolibri user
RUN useradd -m -d ${KOLIBRI_HOME} kolibri

# Install dependencies and create venv
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        libffi-dev \
        libssl-dev \
        libjpeg-dev \
        zlib1g-dev \
        libxml2-dev \
        libxslt1-dev \
        git && \
    python -m venv /opt/venv && \
    /opt/venv/bin/pip install --upgrade pip setuptools wheel && \
    rm -rf /var/lib/apt/lists/*

# Install Kolibri
RUN /opt/venv/bin/pip install --no-cache-dir kolibri

# Set permissions
RUN mkdir -p ${KOLIBRI_HOME} && chown -R kolibri:kolibri ${KOLIBRI_HOME}

# Clean up build deps
RUN apt-get purge -y build-essential gcc git && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

USER kolibri
ENV HOME=${KOLIBRI_HOME}


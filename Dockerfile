FROM ubuntu:18.04
MAINTAINER support@civisanalytics.com

RUN DEBIAN_FRONTEND=noninteractive apt-get update -y --no-install-recommends && \
  apt-get install -y --no-install-recommends locales && \
  locale-gen en_US.UTF-8 && \
  apt-get install -y --no-install-recommends software-properties-common && \
  apt-get install -y --no-install-recommends \
        make \
        automake \
        libpq-dev \
        libffi-dev \
        gfortran \
        g++ \
        git \
        libboost-program-options-dev \
        libtool \
        libxrender1 \
        wget \
        ca-certificates \
        curl && \
  apt-get clean -y && \
  rm -rf /var/lib/apt/lists/*

# Set environment variables for UTF-8, conda, and shell environments
ENV LANG=en_US.UTF-8 \
    LANGUAGE=en_US:en \
    LC_ALL=en_US.UTF-8 \
    CONDARC=/opt/conda/.condarc \
    BASH_ENV=/etc/profile \
    PATH=/opt/conda/bin:$PATH \
    CIVIS_MINICONDA_VERSION \
    CIVIS_CONDA_VERSION \
    CIVIS_PYTHON_VERSION

# Conda install.
#
# Everything is installed in the root environment. This allows for
# upgrades to the packages and eliminates the pain of trying to activate
# some other environment automatically for the many different ways
# people can use a docker image.
#
# Things are pinned to prevent upgrades from conda and force it to
# resolve dependencies relative to a fixed conda & python version.
#
# Note that the python version is also listed in the environment.yml
# file. The version in CIVIS_PYTHON_VERSION is the source of truth.
# If you want to change the python version, you need to change it in
# **both** places. The python version has been left in the `environment.yml`
# file so that people can create environments equivalent to this
# container.
#
# The ordering of these steps seems to matter. You seem to have to
# install a specific python version by hand and then pin it.
# 1) install conda using CIVIS_MINICONDA_VERSION (may not be most up to date conda version)
# 2) pin conda to the version given by CIVIS_CONDA_VERSION
# 3) install the python version CIVIS_PYTHON_VERSION
# 4) pin the python version
#
# Extra symlinks are added at the end because...
#   Red Hat and Debian use different names for this file. git2R wants the latter.
#   See conda-recipes GH 423
RUN echo 'export PATH=/opt/conda/bin:$PATH' > /etc/profile.d/conda.sh && \
    wget --quiet https://repo.continuum.io/miniconda/Miniconda3-${CIVIS_MINICONDA_VERSION}-Linux-x86_64.sh && \
    /bin/bash /Miniconda3-${CIVIS_MINICONDA_VERSION}-Linux-x86_64.sh -b -p /opt/conda && \
    rm Miniconda3-${CIVIS_MINICONDA_VERSION}-Linux-x86_64.sh && \
    /opt/conda/bin/conda install --yes conda==${CIVIS_MINICONDA_VERSION} && \
    conda install conda=${CIVIS_CONDA_VERSION} && \
    echo "conda ==${CIVIS_CONDA_VERSION}" > /opt/conda/conda-meta/pinned && \
    conda install --yes python==${CIVIS_PYTHON_VERSION} && \
    echo "python ==${CIVIS_PYTHON_VERSION}" >> /opt/conda/conda-meta/pinned && \
    conda clean --all -y && \
    ln -s /opt/conda/lib/libopenblas.so /opt/conda/lib/libblas.so && \
    ln -s /opt/conda/lib/libopenblas.so /opt/conda/lib/liblapack.so && \
    ln -s /opt/conda/lib/libssl.so /opt/conda/lib/libssl.so.6 && \
    ln -s /opt/conda/lib/libcrypto.so /opt/conda/lib/libcrypto.so.6

# Install boto in the base environment for private s3 channel support.
# Install Python Packages
COPY .condarc /opt/conda/.condarc
COPY environment.yml environment.yml
RUN conda install -y boto && \
    conda install -y nomkl && \
    conda env update -f environment.yml -n root && \
    conda clean --all -y && \
    rm -rf ~/.cache/pip

# We aren't running a GUI, so force matplotlib to use
# the non-interactive "Agg" backend for graphics.
# Run matplotlib once to build the font cache.
ENV MATPLOTLIBRC=${HOME}/.config/matplotlib/matplotlibrc
RUN mkdir -p ${HOME}/.config/matplotlib && \
    echo "backend      : Agg" > ${HOME}/.config/matplotlib/matplotlibrc && \
    python -c "import matplotlib.pyplot"

# Enable widgetsnbextension for jupyter widgets.
# See https://ipywidgets.readthedocs.io/en/stable/user_install.html.
# This enables the extension in the conda environment. The conda-forge version
# does this upon installation, but the default channel version doesn't seem to,
# so we'll run this (again) just in case.
RUN jupyter nbextension enable --py widgetsnbextension

# Instruct joblib to use disk for temporary files. Joblib defaults to
# /shm when that directory is present. In the Docker container, /shm is
# present but defaults to 64 MB.
# https://github.com/joblib/joblib/blob/0.11/joblib/parallel.py#L328L342
ENV JOBLIB_TEMP_FOLDER=/tmp

ENV VERSION=6.3.1 \
    VERSION_MAJOR=6 \
    VERSION_MINOR=3 \
    VERSION_MICRO=1

# adding selenium, etc here:
FROM python:3.8-alpine3.12

# update apk repo
RUN echo "http://dl-4.alpinelinux.org/alpine/v3.12/main" >> /etc/apk/repositories && \
    echo "http://dl-4.alpinelinux.org/alpine/v3.12/community" >> /etc/apk/repositories

# install chromedriver
RUN apk update
RUN apk add chromium chromium-chromedriver

# install selenium
RUN pip install selenium # ==3.13.0

# install pandas
RUN apk add make automake gcc g++ subversion git python3-dev	
RUN pip install numpy
RUN pip install pandas --upgrade

 # install civis
RUN pip install civis

# install google cloud storage
RUN pip install google-cloud-storage # ==1.29.0

# install Pillow requirements
RUN apk add build-base py-pip jpeg-dev zlib-dev
ENV LIBRARY_PATH=/lib:/usr/lib
RUN pip install Pillow

# Add sudo, because we need it to kill the swap memory every so often
# http://www.yourownlinux.com/2013/10/how-to-free-up-release-unused-cached-memory-in-linux.html
RUN apk --no-cache add sudo

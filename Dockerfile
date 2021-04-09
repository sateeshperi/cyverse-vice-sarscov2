FROM cyversevice/jupyterlab-datascience

user root 

WORKDIR /usr/local/src
ENV PATH=/opt/conda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV TERM=xterm
ENV DEBIAN_FRONTEND=noninteractive

# install conda packages
COPY ./environment.yml /usr/local/src
RUN conda update -n base -c defaults conda
RUN conda env update -n base -f environment.yml && \
    conda clean --all


# Copy source files
RUN export PATH=${PATH}
RUN export TERM=${TERM}
RUN export DEBIAN_FRONTEND=${DEBIAN_FRONTEND}

COPY "./src_files/trimmomatic/*" "./trimmomatic/"
COPY "./src_files/plotcov3/*" "./plotcov3/"
COPY "./src_files/report_to_excel_v3/*" "./report_to_excel_v3/"
COPY "./src_files/scripts/*" "./scripts/"
COPY "./src_files/py_pip3/*" "./py_pip3/"
COPY "./src_files/dot_config/*" "./dot_config/"
COPY "./src_files/dot_config/tz_seed.txt" "/debconf_preseed.txt"
COPY "./src_files/pangolin/requirements.txt" "./pangolin/"



#COPY "./src_files/pangolin/.pyenv/versions/miniconda3-4.7.12/envs/pangolin/bin/pangolin" "./pangolin/"

RUN echo 'debconf debconf/frontend select Noninteractive' | debconf-set-selections
RUN debconf-set-selections /debconf_preseed.txt

# Preinstall packages
RUN apt-get update && apt-get install -y \
     apt-utils \
     autoconf \
     automake \
     bc \
     build-essential \
     cmake \
     ed \
     fonts-texgyre \
     git \
     gosu \
     libbz2-dev \
     libcurl4-openssl-dev \
     libgit2-dev \
     libfindbin-libs-perl \
     libexpat1 \
     fonts-dejavu-core \
     fontconfig-config \
     libfontconfig1 \
     libfreetype6 \
     libpng16-16 \
     liblzma-dev \
     libncurses5 \
     libncurses5-dev \
     libssl-dev \
     libxml2-dev \
     locales \
     libtool \
     openjdk-8-jre \
     parallel \
     sudo \
     meson \
     ninja-build \
     nodejs \
     libvcflib-tools \
     util-linux \
     vim-tiny \
     curl \
     zlib1g-dev \
     make \
     gcc \
     perl \
     libssl-dev


# Install core python3 dependencies through pip
RUN python3 -m pip install -r ./py_pip3/requirements.txt

RUN ln -s /usr/local/src/plotcov3/plotcov3 /usr/local/bin/
RUN ln -s /usr/local/src/report_to_excel_v3/report_to_excel_v3 /usr/local/bin/

RUN bash -c "mkdir ./pangolin/build"
RUN bash -c "cd ./pangolin/build && git clone https://github.com/cov-lineages/pangolin.git"


RUN bash -c "python3 -m pip install -r ./pangolin/requirements.txt"
RUN bash -c "cd ./pangolin/build/pangolin && python setup.py install"


WORKDIR /data

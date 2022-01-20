FROM ubuntu:20.04

ARG DEBIAN_FRONTEND=noninteractive


RUN apt-get update && apt-get install -y vim curl python3 python3-pip openssh-client lsb-release software-properties-common
RUN python3 -m pip install ansible
RUN curl -fsSL https://apt.releases.hashicorp.com/gpg | apt-key add -
RUN apt-add-repository "deb [arch=amd64] https://apt.releases.hashicorp.com $(lsb_release -cs) main"
RUN apt-get update && \
      apt-get install -y terraform && apt-get clean all


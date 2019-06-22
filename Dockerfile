FROM registry.gitlab.com/dwsr/dockerimage-terraform-bundle:0.11.13 AS bundler

ARG TERRAFORM_VERSION=0.11.14

ADD bundle.json /bundle.json

RUN terraform-bundle package /bundle.json && \
  mkdir /tf && \
  unzip terraform_${TERRAFORM_VERSION}-bundle*.zip -d /tf

FROM python:3.7.3-alpine3.9
LABEL maintainer="Brandon McNama <brandonmcnama@outlook.com>"

RUN apk add curl su-exec && \
  addgroup tfuser && \
  adduser -D -G tfuser tfuser && \
  mkdir -p /tf-providers

COPY --from=bundler /tf/terraform-provider-* /tf-providers/

# Download and verify Terraform
ARG TERRAFORM_VERSION=0.11.13

RUN apk add --update git openssh gnupg -t terraform-build && \
  curl https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip > terraform_${TERRAFORM_VERSION}_linux_amd64.zip && \
  curl https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS.sig > terraform_${TERRAFORM_VERSION}_SHA256SUMS.sig && \
  curl https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_SHA256SUMS > terraform_${TERRAFORM_VERSION}_SHA256SUMS && \
  curl https://raw.githubusercontent.com/hashicorp/terraform/master/scripts/docker-release/releases_public_key > releases_public_key && \
  gpg --import releases_public_key && \
  gpg --verify terraform_${TERRAFORM_VERSION}_SHA256SUMS.sig terraform_${TERRAFORM_VERSION}_SHA256SUMS && \
  grep linux_amd64 terraform_${TERRAFORM_VERSION}_SHA256SUMS > terraform_${TERRAFORM_VERSION}_SHA256SUMS_linux_amd64 && \
  sha256sum -cs terraform_${TERRAFORM_VERSION}_SHA256SUMS_linux_amd64 && \
  unzip terraform_${TERRAFORM_VERSION}_linux_amd64.zip -d /bin && \
  rm -f terraform_${TERRAFORM_VERSION}_linux_amd64.zip terraform_${TERRAFORM_VERSION}_SHA256SUMS* releases_public_key && \
  apk del terraform-build

# Download terragrunt
ARG TERRAGRUNT_VERSION=0.18.7

RUN curl -L https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64 > terragrunt_linux_amd64 && \
  curl -L https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/SHA256SUMS > terragrunt_${TERRAGRUNT_VERSION}_SHA256SUMS && \
  grep linux_amd64 terragrunt_${TERRAGRUNT_VERSION}_SHA256SUMS > terragrunt_${TERRAGRUNT_VERSION}_SHA256SUMS_linux_amd64 && \
  sha256sum -cs terragrunt_${TERRAGRUNT_VERSION}_SHA256SUMS_linux_amd64 && \
  mv terragrunt_linux_amd64 /bin/terragrunt && \
  chmod +x /bin/terragrunt && \
  rm -f /terragrunt*

# Configure some default Terraform behaviour. Of specific interest in the fact that Terraform is
# instructed to only look at providers bundled as part of the image, rather than to fetch them from
# the internet, which is the default behaviour. Since this image is intended for use in CI systems,
# this makes sense.
ENV TF_INPUT=0 TF_IN_AUTOMATION=1 TF_CLI_ARGS="-plugin-dir=/tf-providers -get-plugins=false" DISABLE_CHECKPOINT=1

ENTRYPOINT [ "/sbin/su-exec", "tfuser:tfuser" ]
CMD [ "terragrunt" ]

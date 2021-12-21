#!/bin/bash

# ----------------------------------------------------------------------
# Copyright (c) 2021, Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

DIR=$(dirname $0)
ENV_FILE="$DIR/.env"
BASE="$DIR/base"
KOVERLAY="$DIR/overlay"

echoerr() { echo "$@" 1>&2; }

# establish env
if [ ! -f "$ENV_FILE" ]; then
  echoerr "WARN: Configuration $ENV_FILE file does not exist"
else
  echoerr "Source env from $ENV_FILE"
  source ${ENV_FILE}
fi

# validate
if [ -z "$OCIR_REPO" ]; then
  echoerr "ERROR: Requires 'OCIR_REPO' variable ex: 'iad.ocir.io/mytenancy/my-repository'"
  exit 1
fi
if [ -z "$UNREAL_CONTAINER" ]; then
  echoerr "ERROR: Requires 'UNREAL_CONTAINER' variable ex: 'pixeldemo'"
  exit 1
fi

# warnings
if [ -z "$INGRESS_HOST" ]; then
  echoerr "WARN: Recommended 'INGRESS_HOST' variable ex: 'pixeldemo.yyy.yyy.yy.yyy.nip.io'"
fi
if [ -z "$NAMESPACE" ]; then
  echoerr "WARN: Recommended setting 'NAMESPACE' variable (default: pixel)"
fi

# create kustom overlay
echoerr "Create kustomization overlay: $KOVERLAY/"
mkdir -p $KOVERLAY
cd $KOVERLAY

# create patches
echoerr "create patches..."
cat <<EOF > patch-proxy-configmap.yaml
# ----------------------------------------------------------------------
# Copyright (c) 2021, Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

apiVersion: v1
kind: ConfigMap
metadata:
  name: routing-pod-proxy-config
data:
  enable: "${PROXY_ENABLE:-false}"
  # specify the proxy router prefix
  path.prefix: "${PROXY_PATH_PREFIX:-/proxy}"
  # specify comma-separated basic auth users
  auth.users: "${PROXY_AUTH_USERS}"
EOF

cat <<EOF > patch-ingress-host.yaml
# ----------------------------------------------------------------------
# Copyright (c) 2021, Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

- op: replace
  path: /spec/tls/0/hosts/0
  value: ${INGRESS_HOST:-pixeldemo.lb-ip-addr.nip.io}
- op: replace
  path: /spec/rules/0/host
  value: ${INGRESS_HOST:-pixeldemo.lb-ip-addr.nip.io}
EOF

# create overlay
echoerr "create kustomization.yaml..."
cat <<EOF > kustomization.yaml
# ----------------------------------------------------------------------
# Copyright (c) 2021, Oracle and/or its affiliates. All rights reserved.
# The Universal Permissive License (UPL), Version 1.0
# ----------------------------------------------------------------------

# Auto-generated kustomization overlay from ${0}
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: ${NAMESPACE:-pixel}

# extend base
bases:
  - "../base/"

# patches
patchesStrategicMerge:
  # patch the proxy configmap
  - patch-proxy-configmap.yaml

patchesJson6902:
  # patch the ingress hostname
  - path: patch-ingress-host.yaml
    target:
      group: networking.k8s.io
      version: v1
      kind: Ingress
      name: pixelstream-ingress

images:
  # turn image
  - name: turn
    newName: ${OCIR_REPO}/turn
    newTag: ${IMAGE_TAG:-latest}
  # turn aggregator/discovery
  - name: turn-api
    newName: ${OCIR_REPO}/turn-api
    newTag: ${IMAGE_TAG:-latest}
  # pixel streaming
  - name: pixelstreaming
    newName: ${OCIR_REPO}/${UNREAL_CONTAINER}
    newTag: ${IMAGE_TAG:-latest}
  # signal server
  - name: signalserver
    newName: ${OCIR_REPO}/signalserver
    newTag: ${IMAGE_TAG:-latest}
  # matchmaker
  - name: matchmaker
    newName: ${OCIR_REPO}/matchmaker
    newTag: ${IMAGE_TAG:-latest}
  # player webview
  - name: player
    newName: ${OCIR_REPO}/player
    newTag: ${IMAGE_TAG:-latest}
  # dynamic proxy svc
  - name: podproxy
    newName: ${OCIR_REPO}/podproxy
    newTag: ${IMAGE_TAG:-latest}
  # operator tools (kubectl, docker, jq)
  - name: kubetools
    newName: ${OCIR_REPO}/kubetools
    newTag: ${IMAGE_TAG:-latest}
EOF

echoerr "Run kubectl kustomize on $KOVERLAY/kustomization.yaml"
kubectl kustomize .
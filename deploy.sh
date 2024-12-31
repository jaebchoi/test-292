#!/bin/sh

APP_NAME=test-292
INFRA_NAME=infrastructure

print_usage() {
  echo "Usage: $0 [up|down|shutdown]"
  echo "   startup      create/upgrade deployment infrastructure"
  echo "   shutdown     tear down deployment infrastructure (tears down application if needed)"
  echo "   up           deploy application (starts deployment infrastructure if needed)"
  echo "   down         tear down application"
}

startup() {
  echo "Deploying infrastructure..."
  helm upgrade --install $INFRA_NAME test-292-infrastructure \
     --values test-292-infrastructure/values.yaml \
     --values test-292-infrastructure/values-dev.yaml
  if ! kubectl rollout status --namespace argocd deployment/argocd-server --timeout=30s; then
    exit $?
  fi
  argocd repo add https://github.com/jaebchoi/test-292 --server localhost:30080 --plaintext --insecure-skip-server-verification
}

is_app_running() {
  argocd app get $APP_NAME --server localhost:30080 --plaintext > /dev/null 2>&1
}

deploy() {
  echo "Checking for deployment infrastructure..."
  helm status $INFRA_NAME > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    startup
  fi

  if is_app_running; then
    echo "test-292 is deployed"
  else
    branch=$(git rev-parse --abbrev-ref HEAD)
    echo "Deploying test-292 from branch '$branch'..."
    argocd app create $APP_NAME \
      --server localhost:30080 --plaintext \
      --dest-namespace test-292 \
      --dest-server https://kubernetes.default.svc \
      --repo https://github.com/jaebchoi/test-292 \
      --path test-292-deploy/src/main/resources \
      --revision $branch \
      --helm-set spec.targetRevision=$branch \
      --values values.yaml \
      --values values-dev.yaml \
      --sync-policy automated
  fi
}

down() {
  if is_app_running; then
    echo "Tearing down app..."
    argocd app delete $APP_NAME --server localhost:30080 --plaintext --yes
  else
    echo "test-292 is not deployed"
  fi
}

shutdown() {
  helm status $INFRA_NAME > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    echo "Infrastructure already shutdown"
  else
    if is_app_running; then
      down
    fi
    echo "Shutting down infrastructure..."
    helm uninstall $INFRA_NAME
  fi
}


if [ "$1" = "up" ]; then
  deploy
elif [ "$1" = "down" ]; then
  down
elif [ "$1" = "shutdown" ]; then
  shutdown
elif [ "$1" = "startup" ]; then
  startup
else
  print_usage
fi

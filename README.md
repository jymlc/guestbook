# Guestbook Kubernetes final project

Based on the IBM Guestbook starter. The lab app and Kubernetes manifests are in `v1/guestbook`. The v2 HTML and manifest are in `v1/guestbook/release-v2`.

The GitHub Actions workflow builds both container versions, pushes them to a local Docker Registry, deploys to a temporary Kubernetes cluster, drives the CPU autoscaler under load, performs a rolling update, and rolls back to v1. The run summary and artifact contain the actual commands and output.

The registry evidence is explicitly from the local CI registry. For an IBM Container Registry submission, use an authenticated lab session to tag and push to its assigned registry and run `ibmcloud cr images`.

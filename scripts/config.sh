#!/usr/bin/env bash
# Shared configuration for all valserver scripts.
# Override any of these with environment variables before running.

PROJECT="${GCP_PROJECT:-valserver}"
ZONE="${GCP_ZONE:-us-central1-a}"
REGION="${GCP_REGION:-us-central1}"

VM_NAME="valserver"
MACHINE_TYPE="e2-medium"
DISK_NAME="valserver-data"
DISK_SIZE="10"  # GB
FIREWALL_RULE="valserver-allow-valheim"
NETWORK_TAG="valheim-server"

# Valheim server config defaults
SERVER_NAME="${SERVER_NAME:-Valserver}"
SERVER_PASS="${SERVER_PASS:-}"
WORLD_NAME="${WORLD_NAME:-Dedicated}"
SERVER_PUBLIC="${SERVER_PUBLIC:-false}"

# Docker image — pin to a specific tag for reproducibility
VALHEIM_IMAGE="lloesche/valheim-server:latest"

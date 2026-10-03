#!/usr/bin/env bash
# Build+push de backend y frontend a Docker Hub.
# Requiere: docker buildx, builder "$BUILDER" (se crea solo si falta),
# QEMU binfmt solo si pedís arm64, y login en Docker Hub (`docker login`).
# Uso:
#   DOCKER_USER=nachoalbarracin \
#   NEXT_PUBLIC_API_URL=https://api.tu-dominio.com/api NEXT_PUBLIC_CLAVE_ADMIN=... \
#   ./build-and-push.sh [backend|frontend]
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

BACKEND_IMAGE="${BACKEND_IMAGE:-${DOCKER_USER:?set DOCKER_USER}/semana-torneo-backend:latest}"
FRONTEND_IMAGE="${FRONTEND_IMAGE:-${DOCKER_USER:?set DOCKER_USER}/semana-torneo-frontend:latest}"
# Una sola plataforma = la de tu VPS (arm64 acá). El build corre emulado con
# QEMU, lento la primera vez; el cache de registry acelera los siguientes.
# Si tu máquina local fuera arm64, sería nativo y rápido.
# Multi-arch (linux/amd64,linux/arm64) solo para el release final: tarda
# 5-10x y compilar las extensiones PHP bajo QEMU puede morir por OOM con
# "cannot compute suffix of object files: cannot compile" (ver -j2 en el Dockerfile).
PLATFORMS="${PLATFORMS:-linux/arm64}"
BUILDER="${BUILDER:-multiarch}"
# CACHE=0 para desactivar el cache de registry (debug de builds limpios).
CACHE="${CACHE:-1}"
# PUSH=0 para buildear sin pushear (servidor sin docker login): la imagen
# queda cargada en el docker local con --load, lista para `up -d` sin `pull`.
# Con PUSH=0 conviene CACHE=0 (el export de cache también necesita login).
PUSH="${PUSH:-1}"

if [ "$PUSH" != "1" ] && [ "${PLATFORMS#*,}" != "$PLATFORMS" ]; then
  echo "PUSH=0 requiere una sola plataforma (PLATFORMS=$PLATFORMS)" >&2
  exit 1
fi

TARGET="${1:-all}"

docker buildx inspect "$BUILDER" >/dev/null 2>&1 \
  || docker buildx create --name "$BUILDER" --driver docker-container >/dev/null

build_one() {
  local name="$1" context="$2" image="$3"; shift 3
  echo "==> Building+pushing $name ($PLATFORMS)..."
  local cache_args=()
  if [ "$CACHE" = "1" ]; then
    local cache_ref="${image%:*}:buildcache"
    cache_args=(
      --cache-from "type=registry,ref=${cache_ref}"
      --cache-to "type=registry,ref=${cache_ref},mode=max"
    )
  fi
  local deliver_arg=(--push)
  if [ "$PUSH" != "1" ]; then deliver_arg=(--load); fi
  # shellcheck disable=SC2086
  docker buildx build \
    --builder "$BUILDER" \
    --platform "$PLATFORMS" \
    ${cache_args[@]+"${cache_args[@]}"} \
    "$@" \
    -t "$image" \
    "${deliver_arg[@]}" \
    "$context"
}

build_backend() {
  build_one backend "$ROOT/semana-ingenieria-app-back" "$BACKEND_IMAGE"
}

build_frontend() {
  build_one frontend "$ROOT/semana-ingeniera-app-front" "$FRONTEND_IMAGE" \
    --build-arg NEXT_PUBLIC_API_URL="${NEXT_PUBLIC_API_URL:?set NEXT_PUBLIC_API_URL}" \
    --build-arg NEXT_PUBLIC_CLAVE_ADMIN="${NEXT_PUBLIC_CLAVE_ADMIN:?set NEXT_PUBLIC_CLAVE_ADMIN}"
}

case "$TARGET" in
  backend) build_backend ;;
  frontend) build_frontend ;;
  all) build_backend; build_frontend ;;
  *) echo "uso: $0 [backend|frontend]" >&2; exit 1 ;;
esac

echo ""
if [ "$PUSH" = "1" ]; then
  echo "Listo. En el servidor corré:"
  echo "  docker compose -f docker-compose.prod.yaml pull"
  echo "  docker compose -f docker-compose.prod.yaml up -d"
else
  echo "Listo. Imagen local (PUSH=0): levantá SIN pull:"
  echo "  mkdir -p data && touch data/database.sqlite && chmod 666 data/database.sqlite"
  echo "  docker compose up -d"
fi

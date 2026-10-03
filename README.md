# semana-torneo-deploy

Kit de deploy a producción del Torneo Semana Ingeniería.

- Apps (repos separados): `semana-ingenieria-app-back` (Laravel + Apache)
  y `semana-ingeniera-app-front` (Next.js).
- Imágenes: `nachoalbarracin/semana-torneo-backend|frontend:latest`
  (`linux/arm64`, la del VPS).

## Build + push (tu máquina)

```bash
DOCKER_USER=nachoalbarracin \
NEXT_PUBLIC_API_URL=https://api.tu-dominio.com/api NEXT_PUBLIC_CLAVE_ADMIN=... \
./build-and-push.sh [backend|frontend]
```

- `PLATFORMS` (default `linux/arm64`): una sola plataforma; multi-arch solo
  para el release final (lento y puede fallar bajo QEMU).
- `PUSH=0`: buildea sin pushear (útil en el servidor sin `docker login`).
- `CACHE=0`: desactiva el cache de registry.

## Deploy (VPS, `/home/ubuntu/proy/semana-ing`)

El compose de servidor se despliega como `docker-compose.yaml`:

```bash
cp .env.example .env  # completar valores reales
mkdir -p data && touch data/database.sqlite && chmod 666 data/database.sqlite
docker compose pull
docker compose up -d
docker compose exec backend php artisan db:seed --force  # solo primera vez
```

Todo el tráfico externo entra por `cloudflared`: los hostnames se
configuran en el dashboard de Cloudflare Zero Trust, no acá.

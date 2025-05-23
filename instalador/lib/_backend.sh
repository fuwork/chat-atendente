#!/bin/bash
#
# functions for setting up app backend
#######################################
# creates REDIS db using docker
# Arguments:
#   None
#######################################
backend_redis_create() {
  print_banner
  printf "${WHITE} 💻 Criando Redis & Banco Postgres...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # Criar docker-compose.yml para o Redis
  sudo su - deploy << EOF
  mkdir -p /home/deploy/${instancia_add}/redis
  cat > /home/deploy/${instancia_add}/redis/docker-compose.yml << 'END'
version: '3.7'

services:
  redis-${instancia_add}:
    image: redis:latest
    command: redis-server --requirepass ${mysql_root_password}
    networks:
      - network_public
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure

networks:
  network_public:
    external: true
    name: network_public
END

  # Iniciar o Redis como serviço no swarm
  cd /home/deploy/${instancia_add}/redis
  docker stack deploy -c docker-compose.yml redis-${instancia_add}
EOF

  sleep 2

  # Configurar o banco de dados PostgreSQL
  sudo su - root <<EOF
  sudo su - postgres
  createdb ${instancia_add};
  psql
  CREATE USER ${instancia_add} SUPERUSER INHERIT CREATEDB CREATEROLE;
  ALTER USER ${instancia_add} PASSWORD '${mysql_root_password}';
  \q
  exit
EOF

  sleep 2
}

#######################################
# sets environment variable for backend.
# Arguments:
#   None
#######################################
backend_set_env() {
  print_banner
  printf "${WHITE} 💻 Configurando variáveis de ambiente (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # ensure idempotency
  backend_url=$(echo "${backend_url/https:\/\/}")
  backend_url=${backend_url%%/*}
  backend_url=https://$backend_url

  # ensure idempotency
  frontend_url=$(echo "${frontend_url/https:\/\/}")
  frontend_url=${frontend_url%%/*}
  frontend_url=https://$frontend_url

sudo su - deploy << EOF
  cat <<[-]EOF > /home/deploy/${instancia_add}/backend/.env
NODE_ENV=
BACKEND_URL=${backend_url}
FRONTEND_URL=${frontend_url}
PROXY_PORT=443
PORT=${backend_port}

DB_DIALECT=postgres
DB_HOST=localhost
DB_PORT=5432
DB_USER=${instancia_add}
DB_PASS=${mysql_root_password}
DB_NAME=${instancia_add}

JWT_SECRET=${jwt_secret}
JWT_REFRESH_SECRET=${jwt_refresh_secret}

REDIS_URI=redis://:${mysql_root_password}@redis-${instancia_add}_redis-${instancia_add}:6379
REDIS_OPT_LIMITER_MAX=1
REGIS_OPT_LIMITER_DURATION=3000

USER_LIMIT=${max_user}
CONNECTIONS_LIMIT=${max_whats}
CLOSED_SEND_BY_ME=true

[-]EOF
EOF

  sleep 2
}

#######################################
# installs node.js dependencies
# Arguments:
#   None
#######################################
backend_node_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando dependências do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npm install --force
EOF

  sleep 2
}

#######################################
# compiles backend code
# Arguments:
#   None
#######################################
backend_node_build() {
  print_banner
  printf "${WHITE} 💻 Compilando o código do backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npm run build
EOF

  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
backend_update() {
  print_banner
  printf "${WHITE} 💻 Atualizando o backend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${empresa_atualizar}
  pm2 stop ${empresa_atualizar}-backend
  git pull
  cd /home/deploy/${empresa_atualizar}/backend
  npm install
  npm update -f
  npm install @types/fs-extra
  rm -rf dist 
  npm run build
  npx sequelize db:migrate
  npx sequelize db:migrate
  npx sequelize db:seed
  pm2 start ${empresa_atualizar}-backend
  pm2 save 
EOF

  sleep 2
}

#######################################
# runs db migrate
# Arguments:
#   None
#######################################
backend_db_migrate() {
  print_banner
  printf "${WHITE} 💻 Executando db:migrate...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npx sequelize db:migrate
EOF

  sleep 2
}

#######################################
# runs db seed
# Arguments:
#   None
#######################################
backend_db_seed() {
  print_banner
  printf "${WHITE} 💻 Executando db:seed...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  npx sequelize db:seed:all
EOF

  sleep 2
}

#######################################
# starts backend using pm2 in 
# production mode.
# Arguments:
#   None
#######################################
backend_start_pm2() {
  print_banner
  printf "${WHITE} 💻 Iniciando pm2 (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/backend
  pm2 start dist/server.js --name ${instancia_add}-backend
EOF

  sleep 2
}

#######################################
# updates backend code
# Arguments:
#   None
#######################################
backend_traefik_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando Traefik (backend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  backend_hostname=$(echo "${backend_url/https:\/\/}")

  # Criar arquivo docker-compose para o backend
  sudo su - deploy << EOF
  cat > /home/deploy/${instancia_add}/backend/docker-compose.yml << 'END'
version: '3.7'

services:
  ${instancia_add}-backend:
    image: node:20
    working_dir: /app
    volumes:
      - ./:/app
    command: node dist/server.js
    networks:
      - network_public
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.${instancia_add}-backend.rule=Host(\`${backend_hostname}\`)"
        - "traefik.http.routers.${instancia_add}-backend.entrypoints=websecure"
        - "traefik.http.services.${instancia_add}-backend.loadbalancer.server.port=${backend_port}"
        - "traefik.http.routers.${instancia_add}-backend.tls=true"
        - "traefik.http.routers.${instancia_add}-backend.tls.certresolver=letsencryptresolver"
        - "traefik.docker.network=network_public"

networks:
  network_public:
    external: true
    name: network_public
END

  # Iniciar o container como um serviço no swarm
  cd /home/deploy/${instancia_add}/backend
  docker stack deploy -c docker-compose.yml ${instancia_add}-backend
EOF

  sleep 2
}

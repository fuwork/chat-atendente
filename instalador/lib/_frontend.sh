#!/bin/bash
# 
# functions for setting up app frontend

#######################################
# installed node packages
# Arguments:
#   None
#######################################
frontend_node_dependencies() {
  print_banner
  printf "${WHITE} 💻 Instalando dependências do frontend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/frontend
  npm install --force
EOF

  sleep 2
}

#######################################
# compiles frontend code
# Arguments:
#   None
#######################################
frontend_node_build() {
  print_banner
  printf "${WHITE} 💻 Compilando o código do frontend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/frontend
  npm run build
EOF

  sleep 2
}

#######################################
# updates frontend code
# Arguments:
#   None
#######################################
frontend_update() {
  print_banner
  printf "${WHITE} 💻 Atualizando o frontend...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${empresa_atualizar}
  pm2 stop ${empresa_atualizar}-frontend
  git pull
  cd /home/deploy/${empresa_atualizar}/frontend
  npm install
  rm -rf build
  npm run build
  pm2 start ${empresa_atualizar}-frontend
  pm2 save
EOF

  sleep 2
}


#######################################
# sets frontend environment variables
# Arguments:
#   None
#######################################
frontend_set_env() {
  print_banner
  printf "${WHITE} 💻 Configurando variáveis de ambiente (frontend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  # ensure idempotency
  backend_url=$(echo "${backend_url/https:\/\/}")
  backend_url=${backend_url%%/*}
  backend_url=https://$backend_url

sudo su - deploy << EOF
  cat <<[-]EOF > /home/deploy/${instancia_add}/frontend/.env
REACT_APP_BACKEND_URL=${backend_url}
REACT_APP_HOURS_CLOSE_TICKETS_AUTO = 24
[-]EOF
EOF

  sleep 2

sudo su - deploy << EOF
  cat <<[-]EOF > /home/deploy/${instancia_add}/frontend/server.js
//simple express server to run frontend production build;
const express = require("express");
const path = require("path");
const app = express();
app.use(express.static(path.join(__dirname, "build")));
app.get("/*", function (req, res) {
	res.sendFile(path.join(__dirname, "build", "index.html"));
});
app.listen(${frontend_port});

[-]EOF
EOF

  sleep 2
}

#######################################
# starts pm2 for frontend
# Arguments:
#   None
#######################################
frontend_start_pm2() {
  print_banner
  printf "${WHITE} 💻 Iniciando pm2 (frontend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  sudo su - deploy <<EOF
  cd /home/deploy/${instancia_add}/frontend
  pm2 start server.js --name ${instancia_add}-frontend
  pm2 save
EOF

 sleep 2
  
  sudo su - root <<EOF
   pm2 startup
  sudo env PATH=$PATH:/usr/bin /usr/lib/node_modules/pm2/bin/pm2 startup systemd -u deploy --hp /home/deploy
EOF
  sleep 2
}

#######################################
# sets up trafik for frontend
# Arguments:
#   None
#######################################
frontend_traefik_setup() {
  print_banner
  printf "${WHITE} 💻 Configurando Traefik (frontend)...${GRAY_LIGHT}"
  printf "\n\n"

  sleep 2

  frontend_hostname=$(echo "${frontend_url/https:\/\/}")

  # Criar arquivo docker-compose para o frontend
  sudo su - deploy << EOF
  cat > /home/deploy/${instancia_add}/frontend/docker-compose.yml << 'END'
 version: '3.7'

services:
  ${instancia_add}-frontend:
    image: node:20
    working_dir: /app
    volumes:
      - ./:/app
    command: node server.js
    networks:
      - network_public
    deploy:
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.${instancia_add}-frontend.rule=Host(\`${frontend_hostname}\`)"
        - "traefik.http.routers.${instancia_add}-frontend.entrypoints=websecure"
        - "traefik.http.services.${instancia_add}-frontend.loadbalancer.server.port=${frontend_port}"
        - "traefik.http.routers.${instancia_add}-frontend.tls=true"
        - "traefik.http.routers.${instancia_add}-frontend.tls.certresolver=letsencryptresolver"
        - "traefik.docker.network=network_public"

networks:
  network_public:
    external: true
    name: network_public
END

  # Iniciar o container como um serviço no swarm
  cd /home/deploy/${instancia_add}/frontend
  docker stack deploy -c docker-compose.yml ${instancia_add}-frontend
EOF

  sleep 2
}

FROM node:18-bullseye-slim
WORKDIR /app

# manifests first
COPY package*.json ./

# secrets and deps
COPY session.key salt.key ./
RUN npm ci --ignore-scripts || npm install --ignore-scripts
RUN npm install -g pm2

# default configs (only if you don’t already COPY real ones)
# RUN node -e "const fs=require('fs');fs.writeFileSync('.hcserver.json', JSON.stringify({modulesPath:'/tmp/commands', websocketPort:'6060', rateLimit:{halflife:'30000',threshold:'25'}, pulseSpeed:'16000'}, null, 2));"
# RUN node -e "const fs=require('fs'); if(!fs.existsSync('config.json')) fs.writeFileSync('config.json', JSON.stringify({channels:{},bans:[],mods:[]}, null, 2));"

# app
COPY . .

EXPOSE 3000 6060
ENTRYPOINT []
# Seed /tmp/commands each start, then run PM2 in foreground
CMD ["sh","-lc","rm -rf /tmp/commands && cp -a /app/commands /tmp/commands && pm2-runtime pm2.config.cjs"]







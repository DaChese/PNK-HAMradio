FROM node:18-bullseye-slim
WORKDIR /app

# Copy package manifests first
COPY package*.json ./

# If you keep keys in repo: copy them and name as expected
# (or mount them with volumes in compose; your call)
COPY session.key salt.key ./

# Install deps WITHOUT postinstall (avoids interactive config)
RUN npm ci --ignore-scripts || npm install --ignore-scripts

# PM2 in foreground
RUN npm install -g pm2

# Provide default configs the server expects
# (you can also COPY real files instead)
RUN node -e "const fs=require('fs');fs.writeFileSync('.hcserver.json', JSON.stringify({modulesPath:'./commands', websocketPort:'6060', rateLimit:{halflife:'30000',threshold:'25'}, pulseSpeed:'16000'}, null, 2));" \
 && node -e "const fs=require('fs'); if(!fs.existsSync('config.json')) fs.writeFileSync('config.json', JSON.stringify({channels:{},bans:[],mods:[]}, null, 2));"

# Bring in the rest
COPY . .

EXPOSE 3000 6060
ENTRYPOINT []
CMD ["pm2-runtime", "pm2.config.cjs"]






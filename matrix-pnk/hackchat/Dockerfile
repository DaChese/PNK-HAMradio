FROM node:18-bullseye-slim

WORKDIR /app

# Copy manifests first
COPY package*.json ./

# Copy non-interactive key files BEFORE install so postinstall won't prompt
COPY sessionKey.txt tripSalt.txt ./

# Install deps WITHOUT running postinstall scripts (which asks for keys)
RUN npm ci --ignore-scripts || npm install --ignore-scripts

# Install pm2 (provides pm2-runtime)
RUN npm install -g pm2

# Generate config.json from the key files
RUN node -e "const fs=require('fs'); const cfg={ sessionKey:fs.readFileSync('sessionKey.txt','utf8').trim(), tripSalt:fs.readFileSync('tripSalt.txt','utf8').trim(), port:6060 }; fs.writeFileSync('config.json', JSON.stringify(cfg,null,2));"

# Bring in the rest of the app
COPY . .

EXPOSE 3000 6060

# Run PM2 in foreground (avoid container exit)
ENTRYPOINT []
CMD ["pm2-runtime", "pm2.config.cjs"]







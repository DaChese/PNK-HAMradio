FROM node:18-bullseye-slim

WORKDIR /app

# copy manifests first
COPY package*.json ./

# provide non-interactive keys before install so postinstall doesn't prompt
COPY sessionKey.txt tripSalt.txt ./

# install deps without running postinstall scripts
RUN npm ci --ignore-scripts || npm install --ignore-scripts

# install pm2 globally (provides pm2-runtime)
RUN npm install -g pm2

# bring in the rest of the app
COPY . .

EXPOSE 3000 6060

# IMPORTANT: disable Node's default entrypoint so we can run a non-node binary
ENTRYPOINT []

# keep pm2 in foreground so container stays up
CMD ["pm2-runtime", "pm2.config.cjs"]






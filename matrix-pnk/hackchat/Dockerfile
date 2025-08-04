# matrix-pnk/hackchat/Dockerfile

FROM node:18-bullseye-slim

WORKDIR /app

# Install PM2 globally first
RUN npm install -g pm2

# Copy in the full HackChat repo
COPY . .

# Install local dependencies (like ws, express, etc.)
RUN npm install

EXPOSE 6060

# Use pm2-runtime to run config without daemonizing
CMD ["pm2-runtime", "pm2.config.cjs"]

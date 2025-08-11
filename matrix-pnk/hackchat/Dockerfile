FROM node:18-bullseye-slim

WORKDIR /app
COPY package*.json ./
RUN npm ci || npm install

# bring the app in (make sure your working hackchat repo is here)
COPY . .

# expose WS and HTTP ports used by pm2 config (adjust if your pm2 config differs)
EXPOSE 6060 3000

# run the pm2 config that starts websocket + http server
CMD ["npm", "start"]

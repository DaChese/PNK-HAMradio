FROM node:18-bullseye-slim

WORKDIR /app

COPY . .

# Install dependencies and update
RUN npm install \
    && npm update \
    && npm install -g npm@latest

CMD ["node", "main.js"]


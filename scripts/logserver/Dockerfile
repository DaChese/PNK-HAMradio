# scripts/logserver/Dockerfile
FROM node:18-slim
WORKDIR /app
COPY server.js .
RUN apt-get update \
 && apt-get install -y --no-install-recommends docker.io ca-certificates curl \
 && rm -rf /var/lib/apt/lists/* \
 && npm install express cors
CMD ["node", "server.js"]


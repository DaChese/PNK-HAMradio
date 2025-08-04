FROM node:18-bullseye-slim

# System deps for canvas + phantomjs
RUN apt-get update && apt-get install -y \
  libcairo2-dev \libjpeg62-turbo-dev \libpango1.0-dev libgif-dev \
  build-essential g++ \
  && rm -rf /var/lib/apt/lists/*

RUN npm install -g node-gyp

WORKDIR /app

COPY . .

RUN rm -rf node_modules/phantomjs-prebuilt || true \
  && npm install \
  && npm install phantom-render-stream

CMD ["node", "main.js"]

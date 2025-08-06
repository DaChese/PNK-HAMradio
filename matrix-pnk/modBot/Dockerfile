FROM node:18-bullseye-slim

# Install system dependencies (for canvas support, etc.)
RUN apt-get update && apt-get install -y \
  libcairo2-dev \
  libjpeg62-turbo-dev \
  libpango1.0-dev \
  libgif-dev \
  build-essential \
  g++ \
  && rm -rf /var/lib/apt/lists/*

# Install node-gyp globally (optional, but useful for native builds)
RUN npm install -g node-gyp

# Set working directory inside the container
WORKDIR /app

# Copy project files (optional — include if building from Docker context)
# COPY . .

# Install dependencies
RUN npm install

# Start the app
CMD ["node", "main.js"]

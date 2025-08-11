FROM node:18-bullseye-slim

WORKDIR /app

# Copy package manifests first for better caching
COPY package*.json ./

# Copy the non-interactive config files BEFORE install so postinstall doesn't prompt
COPY sessionKey.txt tripSalt.txt ./

# Install deps (postinstall will see the files and skip prompting)
RUN npm ci || npm install

# Now bring in the rest of the app
COPY . .

EXPOSE 3000 6060
CMD ["npm", "start"]


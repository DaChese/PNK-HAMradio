FROM node:18-bullseye-slim

WORKDIR /app

# Bring the whole repo in first so postinstall can find ./scripts/config.js
COPY . .

# Ensure non-interactive config has the files it expects
# (create these in your repo root or mount them via volumes)
# If you already have them in the repo, these COPYs are harmless.
COPY sessionKey.txt ./sessionKey.txt
COPY tripSalt.txt   ./tripSalt.txt

# Install deps (postinstall will see the files and will not prompt)
RUN npm ci || npm install

EXPOSE 3000 6060
CMD ["npm", "start"]



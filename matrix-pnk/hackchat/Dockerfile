FROM node:18-bullseye-slim

WORKDIR /app

# bring in the whole repo (scripts/config.js needs to exist in the tree)
COPY . .

# provide non-interactive config files (create these in your repo root first)
#   matrix-pnk/hackchat/sessionKey.txt
#   matrix-pnk/hackchat/tripSalt.txt
COPY sessionKey.txt ./sessionKey.txt
COPY tripSalt.txt   ./tripSalt.txt

# install deps WITHOUT running postinstall (which prompts)
RUN npm ci --ignore-scripts || npm install --ignore-scripts

EXPOSE 3000 6060
CMD ["pm2-runtime", "pm2.config.cjs"]





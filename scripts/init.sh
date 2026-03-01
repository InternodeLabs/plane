./scripts/docker-reset.sh

# 2. Make sure you are on the right NPM and corepack is correct
nvm use 22.18.0  
rm -rf ~/.cache/node/corepack
corepack disable
corepack enable
corepack prepare pnpm@latest --activate
pnpm -v

# 3. Install packages
pnpm install

# 4. Build all packages
pnpm turbo run build --force 

# 5. Run dev mode
./scripts/dev-start.sh
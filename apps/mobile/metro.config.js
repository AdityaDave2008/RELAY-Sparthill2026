// Metro configuration for the RELAY monorepo.
// Lets Metro resolve the workspace package @relay/core (whose `exports` points
// at TypeScript source) and share a single node_modules from the repo root.
const { getDefaultConfig } = require('expo/metro-config');
const path = require('path');

const projectRoot = __dirname;
const workspaceRoot = path.resolve(projectRoot, '../..');

const config = getDefaultConfig(projectRoot);

// 1. Watch all files in the monorepo so changes to @relay/core are picked up.
config.watchFolders = [workspaceRoot];

// 2. Resolve modules from both the app and the repo root node_modules.
config.resolver.nodeModulesPaths = [
  path.resolve(projectRoot, 'node_modules'),
  path.resolve(workspaceRoot, 'node_modules'),
];

// 3. @relay/core ships raw .ts source via its package `exports`; make sure
//    Metro treats .ts/.tsx as source extensions (Expo already does, but keep
//    explicit for the workspace package).
config.resolver.sourceExts = Array.from(
  new Set([...config.resolver.sourceExts, 'ts', 'tsx', 'cjs', 'mjs']),
);

// 4. Prefer the repo-root copy of React / React Native so the workspace package
//    and the app don't load duplicate copies.
config.resolver.disableHierarchicalLookup = false;

module.exports = config;

import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-ethers";
import "@nomiclabs/hardhat-etherscan";
import "@nomiclabs/hardhat-waffle";
import "@typechain/hardhat";
import { config as dotenvConfig } from "dotenv";
import * as fs from "fs";
import "hardhat-abi-exporter";
import "hardhat-contract-sizer";
import "hardhat-contract-sizer";
import "hardhat-gas-reporter";
import "hardhat-interface-generator";
import "hardhat-preprocessor";
import { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } from "hardhat/builtin-tasks/task-names";
import { HardhatUserConfig, subtask } from "hardhat/config";
import { NetworkUserConfig } from "hardhat/types";
import { resolve } from "path";
import "solidity-coverage";
import "solidity-docgen";

// import "./tasks/accounts";
// import "./tasks/deployContracts";
// import "./tasks/setupLocalEnv";

// @dev ignore imports used in foundry testing suite
// Add a subtask that sets the action for the TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS task
subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, __, runSuper) => {
  // Get the list of source paths that would normally be passed to the Solidity compiler
  const paths = await runSuper();

  // Apply a filter function to exclude paths that contain the string "ignore"
  return paths.filter((p: any) => !p.includes("Constants.sol"));
});

dotenvConfig({ path: resolve(__dirname, "./.env") });

// Ensure that we have all the environment variables we need.
const mnemonic: string | undefined = process.env.MNEMONIC;
if (!mnemonic) {
  throw new Error("Please set your MNEMONIC in a .env file");
}

const infuraApiKey: string | undefined = process.env.INFURA_API_KEY;
if (!infuraApiKey) {
  throw new Error("Please set your INFURA_API_KEY in a .env file");
}

const mainnetUrl: string | undefined = process.env.MAINNET_URL;
if (!mainnetUrl) {
  throw new Error("Please set your MAINNET_URL in a .env file");
}

const chainIds = {
  "arbitrum-mainnet": 42161,
  avalanche: 43114,
  bsc: 56,
  hardhat: 1337,
  mainnet: 1,
  "optimism-mainnet": 10,
  "polygon-mainnet": 137,
  "polygon-mumbai": 80001,
  rinkeby: 4,
};

function getRemappings() {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => line.trim().split("="));
}

function getChainConfig(chain: keyof typeof chainIds): NetworkUserConfig {
  let jsonRpcUrl: string;
  switch (chain) {
    case "avalanche":
      jsonRpcUrl = "https://api.avax.network/ext/bc/C/rpc";
      break;
    case "bsc":
      jsonRpcUrl = "https://bsc-dataseed1.binance.org";
      break;
    default:
      jsonRpcUrl = "https://" + chain + ".infura.io/v3/" + infuraApiKey;
  }
  return {
    // accounts: [process.env.PK],
    accounts: { mnemonic },
    chainId: chainIds[chain],
    url: jsonRpcUrl,
    timeout: 40000,
  };
}

const config: HardhatUserConfig = {
  defaultNetwork: "hardhat",
  etherscan: {
    apiKey: {
      arbitrumOne: process.env.ARBISCAN_API_KEY,
      avalanche: process.env.SNOWTRACE_API_KEY,
      bsc: process.env.BSCSCAN_API_KEY,
      mainnet: process.env.ETHERSCAN_API_KEY,
      optimisticEthereum: process.env.OPTIMISM_API_KEY,
      polygon: process.env.POLYGONSCAN_API_KEY,
      polygonMumbai: process.env.POLYGONSCAN_API_KEY,
      rinkeby: process.env.ETHERSCAN_API_KEY,
    },
  },
  gasReporter: {
    currency: "USD",
    enabled: process.env.REPORT_GAS ? true : false,
    excludeContracts: [],
    src: "./contracts",
  },
  networks: {
    hardhat: {
      gas: "auto",
      accounts: {
        mnemonic,
      },
      chainId: chainIds.hardhat,
      forking: {
        url: mainnetUrl,
        blockNumber: 16474174,
      },
    },
    arbitrum: getChainConfig("arbitrum-mainnet"),
    avalanche: getChainConfig("avalanche"),
    bsc: getChainConfig("bsc"),
    mainnet: {
      accounts: [process.env.PK],
      // accounts: {
      //   mnemonic,
      // },
      chainId: chainIds.mainnet,
      url: mainnetUrl,
    },
    optimism: getChainConfig("optimism-mainnet"),
    "polygon-mainnet": {
      accounts: [process.env.PK],
      chainId: chainIds["polygon-mainnet"],
      url: "https://polygon-mainnet.infura.io/v3/9bebaa85ce444079a74b66ea2b77b090",
      timeout: 100000,
    },
    "polygon-mumbai": getChainConfig("polygon-mumbai"),
    rinkeby: getChainConfig("rinkeby"),
  },
  paths: {
    artifacts: "./artifacts",
    cache: "./cache",
    sources: "./src",
    tests: "./src/test",
  },
  solidity: {
    compilers: [
      {
        version: "0.8.19",
        settings: {
          metadata: {
            // Not including the metadata hash
            // https://github.com/paulrberg/solidity-template/issues/31
            bytecodeHash: "none",
          },
          // Disable the optimizer when debugging
          // https://hardhat.org/hardhat-network/#solidity-optimizer-support
          viaIR: true,
          optimizer: {
            enabled: true,
            runs: 100_000,
            // runs: 1_660,
          },
        },
      },
    ],
  },
  typechain: {
    outDir: "typechain",
    target: "ethers-v5",
  },
  abiExporter: {
    path: "./data/abi",
  },
  docgen: {
    outputDir: "documentation/docgen",
    pages: "files",
    templates: "documentation/themes/markdown",
  },
  preprocess: {
    eachLine: (hre) => ({
      transform: (line: string) => {
        if (line.match(/^\s*import /i)) {
          getRemappings().forEach(([find, replace]) => {
            if (line.match('"' + find)) {
              line = line.replace('"' + find, '"' + replace);
            }
          });
        }
        return line;
      },
    }),
  },
  contractSizer: {
    runOnCompile: true,
    only: [":FraxlendPair"],
  },
};

export default config;

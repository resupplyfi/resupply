import { exec } from "child_process";
import * as fs from "fs";
import path from "path";

const generateSingleInterface = (name) => {
  const interfaceName = `I${name}`;
  const pathToAbi = path.resolve(__dirname, `../out/${name}.sol/${name}.json`);
  const pragma = "0.8.19";
  const pathToOutput = path.resolve(__dirname, `../${interfaceName}.sol`);
  const command = `cast interface ${pathToAbi} --name ${interfaceName} -p ${pragma}`;
  exec(command, (error, stdout, stderr) => {
    const license = "// SPDX-License-Identifier: UNLICENSED\n";
    fs.writeFileSync(pathToOutput, license + stdout);
    console.error(stderr);
  });
};

const main = async () => {
  // get first arg
  const names = process.argv.slice(2);

  names.forEach(generateSingleInterface);
};
void main();

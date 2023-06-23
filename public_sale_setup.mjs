import { ethers } from "ethers";
import { config as loadEnv } from 'dotenv';
import { promises } from "fs";
import fs from 'fs';
import { createInterface } from 'readline';
const fsPromises = promises;
loadEnv();

const PRIVATE_KEY = process.env.WALLET_PRIVATE_KEY;
const TOKEN_CONTRACT_ADDRESS = "0x5757077dC977EEF5c9479d8496C3C9E399b80E88";
const SALE_CONTRACT_ADDRESS = "0xAC60EF2147a26950EdD76209f7B485C283ff2BA9";
const TOKEN_ABI_FILE_PATH = './build/contracts/BraqToken.json';
const SALE_ABI_FILE_PATH = './build/contracts/BraqPublicSale.json';
const WHITELIST_CSV_PATH = './whiteList.csv';

//const provider = ethers.getDefaultProvider(`https://sepolia.infura.io/v3/0cbd49cd77ed4132b497031ffc95da6a`);
const provider = ethers.getDefaultProvider(`https://sepolia.infura.io/v3/b4ceed0a8862403d802e4bb169d3cb14`);
const signer = new ethers.Wallet(PRIVATE_KEY, provider);

async function getContract(contractAddress, ABIfilePath){
    const data = await fsPromises.readFile(ABIfilePath, 'utf8');
    const abi = JSON.parse(data)['abi'];
    //console.log(abi);
    return new ethers.Contract(contractAddress, abi, signer);
}
const token_contract = await getContract(TOKEN_CONTRACT_ADDRESS, TOKEN_ABI_FILE_PATH);
const sale_contract = await getContract(SALE_CONTRACT_ADDRESS, SALE_ABI_FILE_PATH);
//console.log(sale_contract);

async function readAddressesFromCSV(WLfilePath) {
    const addresses = [];
    const fileStream = fs.createReadStream(WLfilePath);
    const rl = createInterface({
      input: fileStream,
      crlfDelay: Infinity
    });
    for await (const line of rl) {
      const address = line.trim();
      addresses.push(address);
    }
  
    return addresses;
}

// Setup functions 
export async function setToken(tokenAddress){
    const set = sale_contract.setTokenContract(tokenAddress);
    return set;
}

export async function mintTokens(_to, _amount){
    const mint = await token_contract.mint(_to, _amount);
    return mint;
}

export async function addToWhiteList(array){
    const added = await sale_contract.addToWhitelist(array);
    return added;
}

export async function startPublicSale(){
    const started = await sale_contract.startPublicSale();
    return started;
}

export async function stopPublicSale(){
    const stoped = await sale_contract.stopPublicSale();
}
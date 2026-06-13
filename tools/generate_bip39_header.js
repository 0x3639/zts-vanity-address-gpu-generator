const fs = require('fs');

const inputPath = process.argv[2];
const outputPath = process.argv[3];

if (!inputPath || !outputPath) {
  console.error('Usage: node tools/generate_bip39_header.js <english.txt> <output.cuh>');
  process.exit(64);
}

const words = fs.readFileSync(inputPath, 'utf8').trim().split(/\r?\n/);

if (words.length !== 2048) {
  throw new Error(`expected 2048 words, got ${words.length}`);
}

const maxWordLength = Math.max(...words.map((word) => word.length));
if (maxWordLength > 8) {
  throw new Error(`BIP39 word table storage expects max length <= 8, got ${maxWordLength}`);
}

const quote = (word) => `    "${word.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;

let output = '';
output += '// Generated from the BIP-39 English wordlist. Do not edit by hand.\n';
output += '#pragma once\n\n';

output += 'static constexpr char kHostBip39Words[2048][9] = {\n';
output += words.map(quote).join(',\n');
output += '\n};\n\n';

output += '__device__ __constant__ char kBip39Words[2048][9] = {\n';
output += words.map(quote).join(',\n');
output += '\n};\n\n';

output += '__device__ __constant__ unsigned char kBip39WordLengths[2048] = {\n';
output += words.map((word) => `    ${word.length}`).join(',\n');
output += '\n};\n';

fs.writeFileSync(outputPath, output);

---
title: Crypto puzzle
date: 2021-11-28 18:14
layout: post
---

A cryptocurrency project MILLIONSY launched a [rather interesting puzzle](https://millionsyio.medium.com/puzzle-run-puzzle-be-cool-and-rich-446f2dd88289) recently, with a prize money to whoever solves it first.

I wanted to share my solution.

As you might know Solana wallets can be recovered either by a seed phrase or a private key. We are not interested in seed phrase, let's talk about the private key method.

The private key is a list of 64 numbers (each in the range of 0-255, or 1 byte). Calling it "private key" is actually a bit misleading, because its right half, i.e. the last 32 numbers, represent the public key. 

Solana wallet address is also a public key, encoded in base58 format. If we decode the address in the puzzle - `t1yxcwUcUTWD6BL4PDJmCCznmw4KrsXaXkNpViwQrkE`, we get this sequence in hex notation (spaces added for clarity):

![Wallet public key](/images/pubkey.png)

This almost matches the right half of the long string posted in the puzzle. You just have to put in some missing zeroes and replace the Y and U characters with hex characters (highlighted in red):

![Matching part](/images/puzzle-match.png)

This must mean that the puzzle string is a private key written in hex notation, because its right half matches the wallet address. However, the first half also contains Y and U characters, not to mention it's 63 characters long, making it one character short. Here's the first half btw:

![First half of the private key](/images/puzzle-first-half.png)

The clue says "YOU CAN BE ANYTHING" which, at the time of solving I thought probably means Y and U can be any hex character. On top of that, one of the them must be replaced by two hex characters to make the first half 64 characters long. The good news is that we can write a program to guess all the variations. If my math is right, that means there are 256 * 5 * 16^4, or over 80 million possible variations. What's important is that a program can bruteforce all of them offline without hitting blockchain (it's a [ed25519](https://en.wikipedia.org/wiki/EdDSA#Ed25519) signature verification, which is used by many crypto projects including Solana). You have to code it in C/C++ though to have it finish in a reasonable time. That's what I did anyway after realizing JS is too slow.

After obtaining the correct sequence we just need to convert its numbers to decimal base and import it in any Solana wallet.

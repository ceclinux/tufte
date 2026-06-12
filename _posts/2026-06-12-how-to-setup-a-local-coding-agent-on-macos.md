---
layout: post
title: "How to Setup a Local Coding Agent on macOS"
date: 2026-06-12
---

Original source: [Original post](<https://ikyle.me/blog/2026/how-to-setup-a-local-coding-agent-on-macos>)

I'd had my internet fail a few times recently leaving me stranded without a coding agent, and so when I saw the ["Gemma 4 now runs 2x faster with MTP"](https://x.com/UnslothAI/status/2065107734916432189) Multi-Token Prediction update for Gemma 4 I decided to have a go at getting it running.

I wanted a local coding agent setup that:

-   was fast enough to actually use on my Mac
-   worked through an OpenAI compatible API (so I could use it in other tools)
-   and preferably could handle screenshots/images when needed, so I can feed it screenshots of what it has made.

And I did! This video is realtime. And shows the agent responding at a perfectly usable speed.

![](/assets/images/imported/how-to-setup-a-local-coding-agent-on-macos/Gemma_4_-_Short.mp4)

After a bit of testing the final setup I ended up with is:

-   [llama.cpp](https://github.com/ggml-org/llama.cpp) built with Metal on macOS
-   Gemma 4 26B-A4B in GGUF format
-   A Q8 MTP draft model for speculative decoding
-   The Gemma 4 multimodal projector
-   [Pi](https://github.com/earendil-works/pi) as the terminal coding agent

This was tested on an Apple M1 Max with 64 GB unified memory, running macOS 15.7.7.

## The Model

The main model is: `gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf`.

Link on Huggingface: [models/unsloth-gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q4\_K\_XL.gguf](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/blob/main/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf)

That file is about 16 GB. With the MTP draft head and multimodal projector the model folder is about 17 GB.

The benchmark prompt was:

`Write a compact Python function that parses a unified diff and returns the changed file paths. Then explain two edge cases.`

Each benchmark generated about 128 tokens.

## Baseline: llama.cpp + Metal

First I ran the main model directly through llama.cpp with Metal acceleration:

`repos/llama.cpp/build/bin/llama-cli \   -m models/unsloth-gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf \   -ngl 999 \   -fa on \   -c 4096 \   -n 128`

Result:

<table><thead><tr><th>Setup</th><th>Prompt tok/s</th><th>Generation tok/s</th></tr></thead><tbody><tr><td>Gemma 4 26B-A4B Q4, llama.cpp Metal</td><td>298.0</td><td>58.2</td></tr></tbody></table>

58 tokens/second is not fast, but is usable, but for coding-agent work you want it to be as fast as possible, especially when the agent is making many tool calls.

## Adding the MTP Draft Model

Gemma 4 now has the [MTP draft model available](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF/blob/main/MTP/gemma-4-26B-A4B-it-Q8_0-MTP.gguf):

`MTP/gemma-4-26B-A4B-it-Q8_0-MTP.gguf`

This can be loaded by llama.cpp as a speculative draft model:

`repos/llama.cpp/build/bin/llama-cli \   -m models/unsloth-gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf \   --model-draft models/unsloth-gemma-4-26B-A4B-it-GGUF/MTP/gemma-4-26B-A4B-it-Q8_0-MTP.gguf \   --spec-type draft-mtp \   --spec-draft-n-max 3 \   -ngl 999 \   -fa on \   -c 4096 \   -n 128`

The first run with MTP came in at 69.2 tokens/second using 4 draft tokens. However, Unsloth's guide on [How to Run MTP Models](https://unsloth.ai/docs/models/mtp) includes this note:

> "We found --spec-draft-n-max 2 is the best starting point however, do not assume 2 is optimal, as performance is hardware-dependent. Try any value from 1 through 6 and use whichever is fastest for your system."

After sweeping `--spec-draft-n-max`, the best result was 72.2 tokens/second with 3 draft tokens.

<table><thead><tr><th>Setup</th><th>Prompt tok/s</th><th>Generation tok/s</th><th>Speedup</th></tr></thead><tbody><tr><td>Main model only</td><td>298.0</td><td>58.2</td><td>1.00x</td></tr><tr><td>Main model + Q8 MTP draft</td><td>295.6</td><td>72.2</td><td>1.24x</td></tr></tbody></table>

The useful part is that prompt processing stayed basically the same, while generation improved by about 24%.

## Tuning MTP

I tested `--spec-draft-n-max` values from 1 to 6.

<table><thead><tr><th><code>--spec-draft-n-max</code></th><th>Prompt tok/s</th><th>Generation tok/s</th></tr></thead><tbody><tr><td>1</td><td>295.5</td><td>68.4</td></tr><tr><td>2</td><td>299.1</td><td>72.0</td></tr><tr><td>3</td><td>295.6</td><td>72.2</td></tr><tr><td>4</td><td>297.3</td><td>70.7</td></tr><tr><td>5</td><td>297.9</td><td>63.7</td></tr><tr><td>6</td><td>296.3</td><td>61.2</td></tr></tbody></table>

On my M1 Max machine, `3` was the fastest, with `2` close enough that either would be fine. Values above that got slower.

## MLX Comparison

I also tested MLX models through `mlx-lm`, to find out which is the faster way to run the model on a Mac, llama.cpp or mlx.

<table><thead><tr><th>Runtime</th><th>Model</th><th>Generation tok/s</th></tr></thead><tbody><tr><td>llama.cpp Metal + MTP</td><td>Unsloth GGUF Q4 + Q8 MTP</td><td>72.2</td></tr><tr><td>llama.cpp Metal</td><td>Unsloth GGUF Q4</td><td>58.2</td></tr><tr><td>MLX-LM</td><td>Unsloth UD MLX 4-bit</td><td>45.8</td></tr><tr><td>MLX-LM</td><td>mlx-community 4-bit</td><td>43.9</td></tr><tr><td>MLX-LM</td><td>mlx-community OptiQ 4-bit</td><td>38.1</td></tr></tbody></table>

I thought MLX (being optimised for the Mac) would be fastest.
However, for this specific setup, llama.cpp was faster than MLX, and llama.cpp with MTP was clearly the best option.

I guess all the effort and tweaking which has gone into llama.cpp over time means it quite well optimised fr macOS despite being cross platform.

I also tried Gemma 4 MTP through [gemma-4-swift-mlx](https://github.com/VincentGourbin/gemma-4-swift-mlx), but the tested 26B 4-bit MLX checkpoints did not match the loader's expected weight keys, and I already had the previous MLX tests, so moved on rather than redownload new models and try to tweak things to match.

## Adding Image Support

For Pi, I also wanted to be able to attach screenshots. The local model entry I setup for it originally declared the model as text-only:

`"input": ["text"]`

That meant Pi did not send image tool output through to the model properly.

The llama.cpp server also needs the Gemma 4 multimodal projector in order for the multi-modal part to work (only [the 12B is natively multi-modal](https://blog.google/innovation-and-ai/technology/developers-tools/introducing-gemma-4-12b/)):

`mmproj-BF16.gguf`

When loaded with `--mmproj`, llama.cpp advertises multimodal support, and Pi can send images.

I re-ran the text benchmark with the projector loaded, just to check it didn't change the speed:

<table><thead><tr><th>Setup</th><th>Projector</th><th>Prompt tok/s</th><th>Generation tok/s</th></tr></thead><tbody><tr><td>llama.cpp Metal + MTP</td><td>none</td><td>120.3</td><td>71.4</td></tr><tr><td>llama.cpp Metal + MTP</td><td><code>mmproj-BF16.gguf</code></td><td>297.4</td><td>72.2</td></tr></tbody></table>

The final run with the projector did not show a text-generation slowdown.

* * *

Now for setup instructions:

## Install llama.cpp

Install dependencies:

`brew install cmake git tmux python@3.11`

Clone and build llama.cpp:

`mkdir -p ~/Developer/ML-Models/Gemma4/repos cd ~/Developer/ML-Models/Gemma4  git clone https://github.com/ggml-org/llama.cpp repos/llama.cpp  cd repos/llama.cpp cmake -B build \   -DCMAKE_BUILD_TYPE=Release \   -DGGML_METAL=ON \   -DGGML_ACCELERATE=ON  cmake --build build --config Release -j`

The build I tested had:

`GGML_METAL=ON GGML_ACCELERATE=ON GGML_BLAS=ON GGML_BLAS_VENDOR=Apple`

## Download the Model Files

Create a Python environment:

`cd ~/Developer/ML-Models/Gemma4 python3.11 -m venv .venv source .venv/bin/activate pip install -U huggingface_hub hf_xet`

Download the files:

`mkdir -p models/unsloth-gemma-4-26B-A4B-it-GGUF  huggingface-cli download unsloth/gemma-4-26B-A4B-it-GGUF \   gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf \   mmproj-BF16.gguf \   MTP/gemma-4-26B-A4B-it-Q8_0-MTP.gguf \   --local-dir models/unsloth-gemma-4-26B-A4B-it-GGUF`

You should end up with:

`models/unsloth-gemma-4-26B-A4B-it-GGUF/   gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf   mmproj-BF16.gguf   MTP/gemma-4-26B-A4B-it-Q8_0-MTP.gguf`

## Start the Local Server

This is the final server command:

`repos/llama.cpp/build/bin/llama-server \   -m models/unsloth-gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf \   --model-draft models/unsloth-gemma-4-26B-A4B-it-GGUF/MTP/gemma-4-26B-A4B-it-Q8_0-MTP.gguf \   --mmproj models/unsloth-gemma-4-26B-A4B-it-GGUF/mmproj-BF16.gguf \   --spec-type draft-mtp \   --spec-draft-n-max 3 \   -ngl 999 \   -fa on \   -c 65536 \   --parallel 1 \   --host 127.0.0.1 \   --port 8080`

The OpenAI-compatible endpoint is:

`http://127.0.0.1:8080/v1`

I used a small `start_server.sh` wrapper so it runs inside tmux:

`#!/usr/bin/env bash set -euo pipefail  ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" SESSION_NAME="${SESSION_NAME:-gemma4-server}" HOST="${HOST:-127.0.0.1}" PORT="${PORT:-8080}" CTX_SIZE="${CTX_SIZE:-65536}" PARALLEL="${PARALLEL:-1}"  LLAMA_SERVER="$ROOT_DIR/repos/llama.cpp/build/bin/llama-server" MODEL="$ROOT_DIR/models/unsloth-gemma-4-26B-A4B-it-GGUF/gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf" DRAFT_MODEL="$ROOT_DIR/models/unsloth-gemma-4-26B-A4B-it-GGUF/MTP/gemma-4-26B-A4B-it-Q8_0-MTP.gguf" MMPROJ="$ROOT_DIR/models/unsloth-gemma-4-26B-A4B-it-GGUF/mmproj-BF16.gguf" LOG_FILE="$ROOT_DIR/logs/llama-server-mtp.log"  mkdir -p "$ROOT_DIR/logs"  tmux new-session -d -s "$SESSION_NAME" -c "$ROOT_DIR" \   "$LLAMA_SERVER \     -m '$MODEL' \     --model-draft '$DRAFT_MODEL' \     --mmproj '$MMPROJ' \     --spec-type draft-mtp \     --spec-draft-n-max 3 \     -ngl 999 \     -fa on \     -c '$CTX_SIZE' \     --parallel '$PARALLEL' \     --host '$HOST' \     --port '$PORT' \     2>&1 | tee -a '$LOG_FILE'"`

Start it:

`chmod +x start_server.sh ./start_server.sh`

Check that the server is running:

`curl http://127.0.0.1:8080/v1/models`

## Configure Pi

Pi reads model providers from:

`~/.pi/agent/models.json`

Add a local provider:

`{   "providers": {     "gemma4-local": {       "name": "Gemma 4 Local",       "baseUrl": "http://127.0.0.1:8080/v1",       "api": "openai-completions",       "apiKey": "local",       "authHeader": false,       "compat": {         "supportsDeveloperRole": false,         "supportsReasoningEffort": false       },       "models": [         {           "id": "gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf",           "name": "Gemma 4 26B-A4B Q4 + MTP",           "reasoning": false,           "input": ["text", "image"],           "contextWindow": 65536,           "maxTokens": 8192,           "cost": {             "input": 0,             "output": 0,             "cacheRead": 0,             "cacheWrite": 0           }         }       ]     }   } }`

The important pieces are:

-   `baseUrl` points to the llama.cpp OpenAI-compatible server.
-   `api` is `openai-completions`.
-   `authHeader` is `false`, because this is a local server.
-   `input` includes both `text` and `image`, otherwise Pi treats it as text-only.

Optionally make it the default in:

`~/.pi/agent/settings.json`

`{   "defaultProvider": "gemma4-local",   "defaultModel": "gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf",   "defaultThinkingLevel": "minimal" }`

Then check Pi can see it:

`pi --offline --list-models gemma`

Expected:

`provider      model                               context  max-out  thinking  images gemma4-local  gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf  65.5K    8.2K     no        yes`

Run Pi using the local model:

`pi --provider gemma4-local --model gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf`

Or use non-interactive mode:

`pi -p --provider gemma4-local --model gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf \   "Explain what this repository does"`

For screenshots:

`pi -p @"/path/to/screenshot.png" "Describe this image and point out anything relevant to the UI"`

## Final Setup

The final local coding-agent stack was:

<table><thead><tr><th>Layer</th><th>Choice</th></tr></thead><tbody><tr><td>Inference runtime</td><td>llama.cpp</td></tr><tr><td>macOS acceleration</td><td>Metal + Accelerate</td></tr><tr><td>Main model</td><td><code>gemma-4-26B-A4B-it-UD-Q4_K_XL.gguf</code></td></tr><tr><td>Draft model</td><td><code>gemma-4-26B-A4B-it-Q8_0-MTP.gguf</code></td></tr><tr><td>MTP setting</td><td><code>--spec-draft-n-max 3</code></td></tr><tr><td>Multimodal projector</td><td><code>mmproj-BF16.gguf</code></td></tr><tr><td>Server</td><td><code>llama-server</code> on <code>127.0.0.1:8080</code></td></tr><tr><td>API</td><td>OpenAI-compatible <code>/v1</code></td></tr><tr><td>Coding agent</td><td>Pi</td></tr><tr><td>Pi model input</td><td><code>["text", "image"]</code></td></tr></tbody></table>

The main conclusion was that the MTP draft model is worth using. On this machine it took Gemma 4 from 58.2 tokens/second to 72.2 tokens/second, while keeping the setup simple enough to run as a local OpenAI-compatible server.

![](/assets/images/imported/how-to-setup-a-local-coding-agent-on-macos/Gemma_4_Offline_Test.mp4)

* * *

**P.S:** Some suggested using `Qwen3.6 35B-A3B` instead of `Gemma 4 26B-A4B`. According to the benchmarks I can find, Qwen is a **much** better coding agent than Gemma 4.
However, it is also slower. `Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf` + `unsloth-Qwen3.6-35B-A3B-MTP-GGUF` + `mmproj-BF16.gguf` results in 55 tk/s, instead of 72 tk/s. Which is quite significant when you are sitting waiting for it.

Download the models:

`mkdir -p models/unsloth-Qwen3.6-35B-A3B-MTP-GGUF  huggingface-cli download unsloth/Qwen3.6-35B-A3B-MTP-GGUF \   Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \   mmproj-BF16.gguf \   --local-dir models/unsloth-Qwen3.6-35B-A3B-MTP-GGUF`

Start the server:

`LLAMA_SERVER=/Users/kylehowells/Developer/ML-Models/Gemma4/repos/llama.cpp/build/bin/llama-server  $LLAMA_SERVER \   -m models/unsloth-Qwen3.6-35B-A3B-MTP-GGUF/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \   --mmproj models/unsloth-Qwen3.6-35B-A3B-MTP-GGUF/mmproj-BF16.gguf \   --spec-type draft-mtp \   --spec-draft-n-max 3 \   -ngl 999 \   -fa on \   -c 65536 \   --parallel 1 \   --host 127.0.0.1 \   --port 8081`

Pi Config:

`{   "providers": {     "qwen36-local": {       "name": "Qwen3.6 Local",       "baseUrl": "http://127.0.0.1:8081/v1",       "api": "openai-completions",       "apiKey": "local",       "authHeader": false,       "compat": {         "supportsDeveloperRole": false,         "supportsReasoningEffort": false       },       "models": [         {           "id": "Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf",           "name": "Qwen3.6 35B-A3B Q4 + MTP",           "reasoning": true,           "input": ["text", "image"],           "contextWindow": 65536,           "maxTokens": 8192,           "cost": {             "input": 0,             "output": 0,             "cacheRead": 0,             "cacheWrite": 0           }         }       ]     }   } }`

![](/assets/images/imported/how-to-setup-a-local-coding-agent-on-macos/Qwen_3.6_-_Offline_Test.mp4)

## References:

-   [unsloth.ai/docs/models/qwen3.6](https://unsloth.ai/docs/models/qwen3.6)
-   [unsloth.ai/docs/models/gemma-4](https://unsloth.ai/docs/models/gemma-4)
-   [unsloth.ai/docs/models/mtp](https://unsloth.ai/docs/models/mtp)
-   [github.com/ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)
-   [github.com/earendil-works/pi](https://github.com/earendil-works/pi)
-   [Introducing Gemma 4 12B: a unified, encoder-free multimodal model](https://blog.google/innovation-and-ai/technology/developers-tools/introducing-gemma-4-12b/)
-   ["MTP enables Google Gemma 4 run ~1.4–2.2× faster with no accuracy loss"](https://x.com/UnslothAI/status/2065107734916432189)
-   [unsloth/gemma-4-26B-A4B-it-GGUF](https://huggingface.co/unsloth/gemma-4-26B-A4B-it-GGUF)
-   [unsloth/Qwen3.6-35B-A3B-MTP-GGUF](https://huggingface.co/unsloth/Qwen3.6-35B-A3B-MTP-GGUF)

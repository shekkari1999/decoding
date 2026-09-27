# 2x RTX PRO 6000 Reproduction Handoff

This is the handoff for a future Codex session after cloning this repository onto a machine with two RTX PRO 6000 GPUs.

## Objective

Reproduce and extend `spec-decode.ipynb` with a 70B target and 7B draft, then compare matched target-only and speculative inference. Measure tokens/s, acceptance rate, forward-pass counts, per-stage latency, and peak memory on each GPU.

## Instructions to Future Codex

1. Read `AGENTS.md` before changing anything.
2. Work in `spec-decode.ipynb` unless the user explicitly requests another file.
3. Add Markdown headings and explain important notebook lines with comments.
4. Do not choose model IDs, precision, sharding, or decoding policy without discussing them with the user.
5. Never request or print a Hugging Face token. Do not commit credentials, weights, environments, caches, or results containing secrets.
6. Inspect exact hardware, topology, drivers, model configs, tokenizer mappings, and disk space before installing or downloading.
7. Validate correctness and cache invariants before measuring throughput.

## Current Repository State

Important files:

- `spec-decode.ipynb`: active notebook.
- `pyproject.toml` and `uv.lock`: Transformers environment.
- `vllm_benchmark.py`: experimental L4-era vLLM script; do not assume it works unchanged.
- `AGENTS.md`: interaction rules.

The notebook currently demonstrates token probabilities, debugger inspection, exact `min(1, p/q)` acceptance, residual `max(p-q, 0)` correction, target and draft KV-cache synchronization, multi-round generation, EOS/token limits, and throughput/acceptance metrics.

Historical L4/Qwen results:

- Qwen2.5-7B Transformers greedy: about 17 tokens/s.
- Qwen2.5-0.5B Transformers greedy: about 55 tokens/s.
- Educational Python speculative sampler at `k=3`: about 12 tokens/s.
- Acceptance in that run: about 32%.

These are reference values, not expected RTX PRO 6000 results.

## First Hardware Audit

Run and save:

```bash
nvidia-smi --query-gpu=index,name,memory.total,driver_version,pci.bus_id --format=csv
nvidia-smi topo -m
python3 --version
docker --version
nvidia-container-cli --version
df -h
```

Confirm whether the cards are 96 GB RTX PRO 6000 Blackwell or an older 48 GB RTX 6000 generation. Do not reason from the product name alone. Inspect topology; tensor parallelism over PCIe has a communication cost and NVLink must not be assumed.

Two 96 GB cards provide 192 GB aggregate VRAM. A BF16 70B target plus BF16 7B draft may fit, but KV caches, workspace, and the TP1 draft can create uneven per-GPU pressure. Verify actual placement and headroom.

## Model Compatibility Gate

Ask for the exact Hugging Face repository IDs. Prefer the same model generation and tokenizer family. Never mix tokenizers merely because model sizes are convenient.

Verify before downloading full weights:

```python
from transformers import AutoConfig, AutoTokenizer

target_id = "<TARGET_MODEL_ID>"
draft_id = "<DRAFT_MODEL_ID>"

target_config = AutoConfig.from_pretrained(target_id)
draft_config = AutoConfig.from_pretrained(draft_id)
target_tokenizer = AutoTokenizer.from_pretrained(target_id)
draft_tokenizer = AutoTokenizer.from_pretrained(draft_id)

print(target_config.vocab_size, draft_config.vocab_size)
print(len(target_tokenizer), len(draft_tokenizer))
print(target_tokenizer.get_vocab() == draft_tokenizer.get_vocab())
```

The notebook can slice differently padded heads when real token mappings match. vLLM may enforce stricter configured vocabulary equality; check the selected vLLM version before committing to the pair.

For gated models, authenticate with a read-only token and accept the model license first:

```bash
hf auth login
```

## Transformers Reproduction

Create the locked environment:

```bash
uv sync
uv run python -c "import torch, transformers; print(torch.__version__, torch.version.cuda, transformers.__version__); print(torch.cuda.device_count())"
```

Do not overwrite the existing Qwen experiment. Add a clearly labelled Llama configuration only after confirming model IDs, precision, and placement.

Start with a short correctness run:

1. prefill both models once;
2. verify tokenizer equality;
3. run one speculative round;
4. inspect target and draft cache lengths;
5. confirm both final caches equal prompt length plus committed tokens;
6. test rejection, full acceptance, EOS, and token-limit paths;
7. then enable multi-round generation and throughput measurement.

### Cache warning

The Transformers version used during development treated negative crop arguments as removal counts:

```python
cache.crop(-tokens_to_remove)
```

A positive argument was interpreted as an absolute final length. Inspect `DynamicCache.crop` after upgrades. This previously caused an incorrect `9 -> 3 -> 4` transition; the correct target transition was `9 -> 6 -> 7`.

Sampling the final draft proposal does not cache that token. After proposing `k` tokens, the draft cache commonly contains only the first `k-1`; catch-up must handle this difference.

## Fair Benchmark Matrix

Never compare unlike decoding policies as if they were equivalent.

Run matched comparisons:

1. Transformers target-only sampling vs Transformers speculative sampling.
2. vLLM target-only greedy vs vLLM speculative greedy.
3. If supported, vLLM target-only stochastic sampling vs vLLM speculative sampling with identical sampling settings.

Hold constant:

- prompts, batch size, concurrency, and output count;
- EOS/min-token behavior;
- temperature, top-p, top-k, and seed policy;
- precision, quantization, tensor parallelism, and model revisions;
- warmup and timing boundaries.

Test `k = 1, 2, 3, 4, 6, 8` over several prompts or seeds. Report median and spread, not one best run.

## Reliable vLLM Plan

Use a pinned official vLLM Docker image rather than installing into the Transformers environment. Check current official installation and speculative-decoding docs first. Record image tag/digest, driver, commands, and engine arguments.

Sanity-check Docker GPU access:

```bash
docker run --rm --gpus all nvidia/cuda:<PINNED_CUDA_TAG> nvidia-smi
```

Target-only template:

```bash
docker run --rm \
  --gpus all \
  --ipc=host \
  --shm-size=16g \
  -e HF_TOKEN \
  -v "$HOME/.cache/huggingface:/root/.cache/huggingface" \
  -p 8000:8000 \
  vllm/vllm-openai:<PINNED_TAG> \
  --model <TARGET_MODEL_ID> \
  --tensor-parallel-size 2 \
  --dtype bfloat16 \
  --max-model-len <CONTEXT_LENGTH>
```

Speculative configuration should resemble:

```bash
--speculative-config '{
  "method": "draft_model",
  "model": "<DRAFT_MODEL_ID>",
  "num_speculative_tokens": 3,
  "draft_tensor_parallel_size": 1
}'
```

Confirm field names against the pinned version. Use `--enforce-eager` only to diagnose compilation/CUDA-graph problems; remove it for performance unless required.

Run target-only and speculative configurations in separate fresh containers. Do not leave notebook models resident while starting vLLM.

## Measurement Procedure

For each configuration:

1. start a fresh process/container;
2. finish loading and compilation;
3. run an untimed warmup;
4. perform several timed repetitions;
5. record token count and termination reason;
6. capture per-GPU memory and utilization;
7. collect acceptance statistics if exposed;
8. validate output policy before interpreting speed.

Suggested result columns:

```text
engine,target,draft,dtype,quantization,tp,k,batch_size,
prompt_tokens,output_tokens,acceptance_rate,target_passes,
latency_seconds,tokens_per_second,peak_gpu0_mib,peak_gpu1_mib
```

Only claim speedup when matched repeated tests consistently show:

```text
speedup = speculative_tokens_per_second / target_only_tokens_per_second > 1
```

## Known Pitfalls

- A faster draft is insufficient when acceptance is low.
- Configured head sizes may differ despite identical real token mappings.
- Python loops and `.item()` calls introduce GPU synchronization overhead.
- Multiple `set_trace()` calls should be traversed with `c`; repeated `n` can enter nested IPython frames.
- Editing notebook source does not update live kernel variables; rerun changed definition/loading cells.
- Do not infer production vLLM performance from the educational Python implementation.
- Do not infer stochastic speculative-sampling performance from a greedy speculative-decoding benchmark.

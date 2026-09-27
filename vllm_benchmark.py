import argparse
import json
import time

import torch
from vllm import LLM, SamplingParams


PROMPT = "Explain speculative decoding in three concise sentences."
TARGET_PATH = "./models/Qwen2.5-7B-Instruct"
DRAFT_PATH = "./models/Qwen2.5-0.5B-Instruct"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--spec-tokens", type=int, default=0)
    args = parser.parse_args()

    engine_args = {
        "model": TARGET_PATH,
        "tokenizer": TARGET_PATH,
        "dtype": "bfloat16",
        "max_model_len": 512,
        "max_num_seqs": 1,
        "gpu_memory_utilization": 0.95,
        "seed": 0,
    }

    if args.spec_tokens:
        # The token mappings are identical, but the checkpoints pad their output
        # heads to different sizes. vLLM therefore needs heterogeneous-vocab mode.
        # vLLM 0.30 currently supports this mode only with greedy draft sampling.
        engine_args["speculative_config"] = {
            "method": "draft_model",
            "model": DRAFT_PATH,
            "num_speculative_tokens": args.spec_tokens,
            "use_heterogeneous_vocab": True,
            "draft_sample_method": "greedy",
        }

    llm = LLM(**engine_args)

    # Warm up CUDA kernels and any compilation before timing.
    warmup_params = SamplingParams(
        temperature=0,
        min_tokens=8,
        max_tokens=8,
        ignore_eos=True,
    )
    llm.generate([PROMPT], warmup_params, use_tqdm=False)

    sampling_params = SamplingParams(
        temperature=0,
        min_tokens=128,
        max_tokens=128,
        ignore_eos=True,
    )
    torch.cuda.synchronize()
    start = time.perf_counter()
    outputs = llm.generate([PROMPT], sampling_params, use_tqdm=False)
    torch.cuda.synchronize()
    seconds = time.perf_counter() - start

    completion = outputs[0].outputs[0]
    generated_tokens = len(completion.token_ids)
    result = {
        "mode": "speculative" if args.spec_tokens else "target_only",
        "spec_tokens": args.spec_tokens,
        "generated_tokens": generated_tokens,
        "seconds": seconds,
        "tokens_per_second": generated_tokens / seconds,
        "text": completion.text,
    }
    print("VLLM_BENCHMARK_RESULT=" + json.dumps(result))


if __name__ == "__main__":
    main()

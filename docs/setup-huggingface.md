# Setup: Hugging Face Inference Endpoints

Use HF Inference Endpoints to try models that are too large for your local GPUs. Spin up a dedicated GPU instance, experiment in FALCON, delete when done.

For models that fit on your hardware, use [Ollama](setup-ollama.md) instead — it's free and local.

## How It Works

You rent a dedicated GPU on Hugging Face running their TGI server. It exposes an OpenAI-compatible API. FALCON points at the URL. All infrastructure management (create, pause, delete) happens in HF's dashboard — FALCON is just a client.

## Get a Token

1. Go to [huggingface.co/settings/tokens](https://huggingface.co/settings/tokens)
2. Create a token (read access is sufficient for inference)
3. Copy it — starts with `hf_`

For gated models (Llama, Gemma, etc.), you must also visit the model page on HF and accept the license agreement with the same account.

## Create an Endpoint

1. Go to [ui.endpoints.huggingface.co](https://ui.endpoints.huggingface.co)
2. Select your model (e.g., `Qwen/Qwen2.5-72B-Instruct`)
3. Pick a GPU (see pricing below)
4. **Enable scale to zero** — this is critical for cost control
5. Set min replicas to **0**, max replicas to **1**
6. Deploy

You get a URL like:
```
https://ab1cd2ef3gh4ij5k.us-east-1.aws.endpoints.huggingface.cloud
```

## Configure in FALCON

```elixir
Falcon.Providers.create_provider(%{
  name: "Qwen 72B (HF)",
  type: "openai",
  base_url: "https://ab1cd2ef3gh4ij5k.us-east-1.aws.endpoints.huggingface.cloud",
  api_key: "hf_..."
})
```

The model appears in FALCON's model dropdown. Create a chat thread, select it, go.

When you're done and delete the endpoint on HF, FALCON will get a connection error on the next request — expected. Clean up the provider entry whenever.

## Pricing

Billed **per hour of GPU runtime**, not per token.

| GPU | VRAM | ~Cost/hr | ~Cost/day (24/7) | Good For |
|---|---|---|---|---|
| Nvidia T4 | 16 GB | ~$0.50 | ~$12 | 7B models |
| Nvidia A10G | 24 GB | ~$1.00 | ~$24 | 7-13B models |
| Nvidia L4 | 24 GB | ~$0.80 | ~$19 | 7-13B models |
| Nvidia A100 (40GB) | 40 GB | ~$4.00 | ~$96 | 34-70B quantized |
| Nvidia A100 (80GB) | 80 GB | ~$6.50 | ~$156 | 70B+ full precision |

## Cost Safety

**HF has no billing alerts, no spending caps, and no auto-shutdown based on cost.** A forgotten endpoint bills until you stop it. This section exists because surprise cloud bills are real.

### Rules for solo experimenting:

1. **Always enable scale to zero.** Always. Set idle timeout to 5-15 minutes. This is your only automatic safety net — the endpoint pauses when idle and stops billing.

2. **Set min replicas to 0.** If min replicas is 1 (the default for some configs), it runs 24/7 regardless of scale-to-zero.

3. **Delete the endpoint when you're done.** Don't just close the browser tab. Go to [ui.endpoints.huggingface.co](https://ui.endpoints.huggingface.co) and delete it. Pausing is second-best. Leaving it running is how you get a $720 bill at the end of the month.

4. **Check your billing page.** [huggingface.co/settings/billing](https://huggingface.co/settings/billing) — make a habit of checking this if you have active endpoints.

5. **Audit active endpoints.** You can list them via API:
   ```bash
   curl -H "Authorization: Bearer hf_..." \
     https://api.endpoints.huggingface.cloud/v2/endpoint
   ```

### Realistic cost for experimenting:

If you spin up an A100 80GB, chat for 2 hours with scale-to-zero, then delete it: **~$13**. That's it. The danger is only if you forget to delete and it stays warm.

## Recommended Models (Large, Worth an Endpoint)

These are the models you'd use HF endpoints for — too big for most home GPUs:

| Model | HF ID | GPU Needed | Notes |
|---|---|---|---|
| Llama 3.1 70B Instruct | `meta-llama/Llama-3.1-70B-Instruct` | A100 80GB | Gated |
| Qwen 2.5 72B Instruct | `Qwen/Qwen2.5-72B-Instruct` | A100 80GB | Strong reasoning |
| Mixtral 8x7B Instruct | `mistralai/Mixtral-8x7B-Instruct-v0.1` | A100 40GB | MoE architecture |
| DeepSeek V2 | `deepseek-ai/DeepSeek-V2-Chat` | A100 80GB | Code + reasoning |
| Command R+ | `CohereForAI/c4ai-command-r-plus` | A100 80GB | Strong tool use |

For 7B-13B models, just run them locally with Ollama. Don't pay for a GPU you don't need.

## Future: Endpoint Cost Guard (Planned)

HF has no billing alerts, but they do have a full endpoint management API. FALCON will eventually use this to protect you automatically.

### What the HF API supports

| Action | Endpoint |
|---|---|
| List all endpoints + status | `GET /v2/endpoint/{namespace}` |
| Get endpoint details | `GET /v2/endpoint/{namespace}/{name}` |
| Pause | `POST /v2/endpoint/{namespace}/{name}/pause` |
| Resume | `POST /v2/endpoint/{namespace}/{name}/resume` |
| Scale to zero | `POST /v2/endpoint/{namespace}/{name}/scale-to-zero` |
| Delete | `DELETE /v2/endpoint/{namespace}/{name}` |

Base URL: `https://api.endpoints.huggingface.cloud`
Auth: `Authorization: Bearer hf_...`

Status values returned: `running`, `paused`, `scaledToZero`, `pending`, `failed`, `initializing`.

**No billing/spending API exists** — you cannot query how much you've spent. But you can calculate cost from the endpoint's instance type + uptime.

### Planned FALCON features

- **Endpoint status dashboard**: Show all active HF endpoints, their status, instance type, and estimated cost/hr directly in FALCON's UI
- **Runtime alerts**: Warn in the chat UI if an endpoint has been in `running` status for longer than a configurable threshold (e.g., 2 hours)
- **Auto-pause**: Periodic GenServer that polls HF endpoints and auto-pauses any that exceed a max runtime without FALCON sending a request
- **Auto-delete**: Optional — auto-delete endpoints after a configurable period (for true "spin up, experiment, forget about it safely" workflows)
- **Session cost estimate**: Track how long an endpoint has been active during your session and show an estimated cost in the thread header

These features would use a stored HF token + namespace to poll the management API. All infrastructure actions (pause, delete) would require confirmation in the UI.

## Agent Mode

Models on HF endpoints support FALCON's agent tools (read/write files, run commands) via the OpenAI-compatible function calling protocol. Tool calling quality at 70B+ is significantly better than smaller models — one of the reasons to try the big ones.

## Other HF Options (Reference)

These exist but aren't the primary use case for FALCON:

### Serverless Inference API (Free Tier)
- Free, rate-limited (~1,000 req/day), smaller models only (no 70B+)
- Good for quick model previews, not serious evaluation
- Base URL: `https://api-inference.huggingface.co`

### TGI Self-Hosted
- Run HF models on your own GPU with Docker
- If you have the GPU for it, this is free — but then you'd probably just use Ollama
- See [TGI docs](https://huggingface.co/docs/text-generation-inference) if interested

### HF Token for FALCON (all options)

All three options use the same token. Configure as an `"openai"` type provider — HF exposes OpenAI-compatible `/v1/chat/completions` endpoints across the board.

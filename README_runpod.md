# ACE-Step 1.5 Music Generation API

Generate high-quality music from text descriptions using ACE-Step 1.5 - an open-source music generation model.

## What's Included

- **ACE-Step 1.5 models** pre-loaded (~15GB)
- **FastAPI server** with REST API endpoints
- **LLM-powered features** for lyrics and caption generation
- **CUDA 12.8** optimized for NVIDIA GPUs

## API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/health` | GET | Health check |
| `/v1/models` | GET | List available models |
| `/release_task` | POST | Create music generation task |
| `/query_result` | POST | Query task results |
| `/create_random_sample` | POST | Generate random music parameters via LLM |
| `/format_input` | POST | Enhance lyrics/caption via LLM |
| `/v1/audio` | GET | Download generated audio |

## Quick Start

Once the pod is running, the API is available at:
```
http://<POD_IP>:8000
```

### Generate Music

```bash
# Create a generation task
curl -X POST http://<POD_IP>:8000/release_task \
  -H "Content-Type: application/json" \
  -d '{
    "caption": "upbeat electronic dance music with heavy bass",
    "lyrics": "[Verse]\nDancing through the night...",
    "duration": 60
  }'

# Query result (use task_id from response)
curl -X POST http://<POD_IP>:8000/query_result \
  -H "Content-Type: application/json" \
  -d '{"task_ids": ["<TASK_ID>"]}'
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ACESTEP_DIT_CONFIG` | `acestep-v15-turbo` | DiT model (turbo for faster generation) |
| `ACESTEP_LM_MODEL` | `acestep-5Hz-lm-1.7B` | Language model size |
| `PORT` | `8000` | API server port |

## GPU Requirements

- Minimum: 8GB VRAM (RTX 3070/4070)
- Recommended: 16GB+ VRAM (RTX 4090, A100)

## Links

- [ACE-Step GitHub](https://github.com/ace-step/ACE-Step-1.5)
- [API Documentation](https://github.com/ace-step/ACE-Step-1.5/blob/main/docs/en/API.md)
- [Docker Image Source](https://github.com/ValyrianTech/ace-step-1.5)

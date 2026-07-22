| Model | Selector | Start | Cost | Intelligence | Taste | Vision |
|---|---|---:|---:|---:|---:|---|
| GPT-5.6 Sol | `openai-codex/gpt-5.6-sol` | medium | 4 | 9 | 6 | yes |
| Fable 5 | `anthropic/claude-fable-5` | high | 5 | 9 | 9 | yes |
| Opus 4.8 | `anthropic/claude-opus-4-8` | xhigh | 7 | 7 | 8 | yes |
| Sonnet 5 | `anthropic/claude-sonnet-5` | medium | 5 | 5 | 7 | yes |
| Grok 4.5 | `{{ .grokSelector }}` | high | 3 | 7 | 6 | yes |
| GLM-5.2 | `ollama/glm-5.2:cloud` | {{ .glmStart }} | 2 | 6 | 7 | no |

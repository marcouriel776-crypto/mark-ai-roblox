# Mark AI · Cliente Groq para Roblox

Script de executor que conecta un personaje de Roblox con la API de Groq (modelos GPT-OSS-20B / 120B).

## Requisitos
- Executor con soporte HTTP (`syn.request` o `request`), como Delta.
- API Key de Groq (gratuita en https://console.groq.com/keys).

## Cómo cargarlo
```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/marcouriel776-crypto/mark-ai-roblox/main/mark-ai.lua"))()

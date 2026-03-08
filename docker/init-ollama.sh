#!/bin/bash
set -e

# Start Ollama server in background
ollama serve &

# Wait for Ollama to be ready
echo "Waiting for Ollama..."
until curl -s http://localhost:11434/api/tags > /dev/null 2>&1; do
  sleep 1
done

echo "Pulling gemma3:4b..."
ollama pull gemma3:4b

echo "Pulling phi4-mini..."
ollama pull phi4-mini

echo "Models ready!"

# Keep alive
wait

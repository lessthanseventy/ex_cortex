# User Guide

Welcome to ExCalibur! This guide will help you get started with setting up and using the application.

## Setup

### Prerequisites

- Elixir 1.14+
- Erlang/OTP 25+
- PostgreSQL 13+
- Ollama (for local LLM support)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/your-org/ex_calibur.git
   cd ex_calibur
   ```

2. Install dependencies:
   ```bash
   mix deps.get
   ```

3. Set up the database:
   ```bash
   mix ecto.create
   mix ecto.migrate
   ```

4. Start the application:
   ```bash
   mix phx.server
   ```

## Configuration

### Environment Variables

Create a `.env` file in the root directory with the following variables:

```bash
DATABASE_URL=postgres://user:password@localhost/ex_calibur
OLLAMA_URL=http://localhost:11434
CLAUDE_API_KEY=your-claude-api-key
```

### Ollama Setup

1. Install Ollama from [ollama.ai](https://ollama.ai/)
2. Pull the required models:
   ```bash
   ollama pull ministral-3:8b
   ollama pull devstral-small-2:24b
   ```

## Usage

### Key Concepts

- **Guilds**: Teams of AI agents with specific roles
- **Members**: Individual AI agents with specific roles and capabilities
- **Quests**: Pipelines that define workflows for AI agents to execute
- **Steps**: Individual tasks within a quest
- **Sources**: External sources of data that can trigger quests
- **Lore**: Knowledge base for the AI agents

### Main Pages

- **Town Square**: Browse and install guild charters
- **Guild Hall**: Manage guild members and their roles
- **Quests**: Create and manage quests and their steps
- **Grimoire**: Browse and search lore entries
- **Library**: Browse and configure data sources
- **Lodge**: View and manage quest outputs and proposals
- **Settings**: Configure application settings and API keys

## Common Pitfalls

### Database Issues

If you encounter database issues, try:
```bash
mix ecto.reset
```

### LLM Connection Issues

If you have issues connecting to Ollama:
1. Ensure Ollama is running
2. Check the URL in your `.env` file
3. Verify that the required models are pulled

### Test Failures

If tests fail due to accessibility snapshots:
```bash
mix excessibility
```

This will regenerate the accessibility snapshots.

## Contributing

Please see `CONTRIBUTING.md` for guidelines on contributing to the project.

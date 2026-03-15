defmodule ExCortexWeb.InstinctLive do
  @moduledoc false
  use ExCortexWeb, :live_view

  alias ExCortex.Settings

  @banners ~w(tech lifestyle business)

  @impl true
  def mount(_params, _session, socket) do
    settings = load_settings()
    banner = Settings.get_banner()

    {:ok,
     assign(socket,
       page_title: "Instinct",
       settings: settings,
       banner: banner,
       saved: nil
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("save_llm", %{"llm" => params}, socket) do
    maybe_put(:ollama_url, params["ollama_url"])
    maybe_put(:anthropic_api_key, params["anthropic_api_key"])
    {:noreply, assign(socket, settings: load_settings(), saved: :llm)}
  end

  @impl true
  def handle_event("save_integrations", %{"integrations" => params}, socket) do
    maybe_put(:github_token, params["github_token"])
    maybe_put(:obsidian_vault, params["obsidian_vault"])
    {:noreply, assign(socket, settings: load_settings(), saved: :integrations)}
  end

  @impl true
  def handle_event("save_config", %{"config" => params}, socket) do
    maybe_put(:model_fallback_enabled, params["model_fallback_enabled"] == "true")
    maybe_put(:ollama_vision_model, params["ollama_vision_model"])
    maybe_put(:default_repo, params["default_repo"])
    {:noreply, assign(socket, settings: load_settings(), saved: :config)}
  end

  @impl true
  def handle_event("set_banner", %{"banner" => banner}, socket) do
    value = if banner in @banners, do: banner
    Settings.set_banner(value)
    {:noreply, assign(socket, banner: value, saved: :banner)}
  end

  @impl true
  def handle_event("navigate", %{"to" => path}, socket) do
    {:noreply, push_navigate(socket, to: path)}
  end

  defp maybe_put(_key, nil), do: :ok
  defp maybe_put(_key, ""), do: :ok
  defp maybe_put(key, value), do: Settings.put(key, value)

  defp load_settings do
    all = Settings.get_all()

    %{
      ollama_url: all["ollama_url"],
      anthropic_api_key: all["anthropic_api_key"],
      github_token: all["github_token"],
      obsidian_vault: all["obsidian_vault"],
      model_fallback_enabled: all["model_fallback_enabled"],
      ollama_vision_model: all["ollama_vision_model"],
      default_repo: all["default_repo"]
    }
  end

  defp configured?(nil), do: false
  defp configured?(""), do: false
  defp configured?(_), do: true

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :banners, @banners)

    ~H"""
    <div class="space-y-6">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Instinct</h1>
        <p class="text-muted-foreground mt-1.5">
          Configure LLM providers, integration keys, feature flags, and lobe selection.
        </p>
      </div>

      <.key_hints hints={[{"s", "save section"}, {"esc", "cancel"}]} />

      <%!-- LLM Provider Config --%>
      <.panel title="LLM Providers">
        <form phx-submit="save_llm" class="space-y-4">
          <div class="space-y-1">
            <div class="flex items-center justify-between">
              <label class="block text-sm font-medium">Ollama URL</label>
              <%= if configured?(@settings.ollama_url) do %>
                <.status color="green" label="configured" />
              <% else %>
                <.status color="amber" label="not set" />
              <% end %>
            </div>
            <input
              type="text"
              name="llm[ollama_url]"
              value={@settings.ollama_url || ""}
              placeholder="http://localhost:11434"
              class="w-full border border-input rounded px-3 py-2 text-sm bg-background font-mono"
            />
            <p class="text-xs text-muted-foreground">Base URL for the local Ollama instance</p>
          </div>

          <div class="space-y-1">
            <div class="flex items-center justify-between">
              <label class="block text-sm font-medium">Anthropic API Key</label>
              <%= if configured?(@settings.anthropic_api_key) do %>
                <.status color="green" label="configured" />
              <% else %>
                <.status color="red" label="not set" />
              <% end %>
            </div>
            <input
              type="password"
              name="llm[anthropic_api_key]"
              value={@settings.anthropic_api_key || ""}
              placeholder="sk-ant-..."
              class="w-full border border-input rounded px-3 py-2 text-sm bg-background font-mono"
            />
            <p class="text-xs text-muted-foreground">
              Required for Claude models (Haiku, Sonnet, Opus)
            </p>
          </div>

          <div class="flex items-center gap-3">
            <.button type="submit" size="sm">Save LLM Config</.button>
            <%= if @saved == :llm do %>
              <span class="text-xs t-green">Saved.</span>
            <% end %>
          </div>
        </form>
      </.panel>

      <%!-- Integration Keys --%>
      <.panel title="Integrations">
        <form phx-submit="save_integrations" class="space-y-4">
          <div class="space-y-1">
            <div class="flex items-center justify-between">
              <label class="block text-sm font-medium">GitHub Token</label>
              <%= if configured?(@settings.github_token) do %>
                <.status color="green" label="configured" />
              <% else %>
                <.status color="red" label="not set" />
              <% end %>
            </div>
            <input
              type="password"
              name="integrations[github_token]"
              value={@settings.github_token || ""}
              placeholder="ghp_..."
              class="w-full border border-input rounded px-3 py-2 text-sm bg-background font-mono"
            />
            <p class="text-xs text-muted-foreground">
              Personal access token for GitHub issues, PRs, and notifications
            </p>
          </div>

          <div class="space-y-1">
            <div class="flex items-center justify-between">
              <label class="block text-sm font-medium">Obsidian Vault</label>
              <%= if configured?(@settings.obsidian_vault) do %>
                <.status color="green" label="configured" />
              <% else %>
                <.status color="amber" label="not set" />
              <% end %>
            </div>
            <input
              type="text"
              name="integrations[obsidian_vault]"
              value={@settings.obsidian_vault || ""}
              placeholder="e.g. notes"
              class="w-full border border-input rounded px-3 py-2 text-sm bg-background font-mono"
            />
            <p class="text-xs text-muted-foreground">
              Vault name used when writing Obsidian notes
            </p>
          </div>

          <div class="flex items-center gap-3">
            <.button type="submit" size="sm">Save Integrations</.button>
            <%= if @saved == :integrations do %>
              <span class="text-xs t-green">Saved.</span>
            <% end %>
          </div>
        </form>
      </.panel>

      <%!-- Feature Flags / Config --%>
      <.panel title="Feature Flags">
        <form phx-submit="save_config" class="space-y-4">
          <div class="space-y-1">
            <div class="flex items-center gap-3">
              <input
                type="checkbox"
                id="model_fallback_enabled"
                name="config[model_fallback_enabled]"
                value="true"
                checked={@settings.model_fallback_enabled == true}
                class="h-4 w-4"
              />
              <label for="model_fallback_enabled" class="text-sm font-medium">
                Model fallback chain enabled
              </label>
            </div>
            <p class="text-xs text-muted-foreground pl-7">
              Automatically retry with backup models when the primary is unavailable
            </p>
          </div>

          <div class="space-y-1">
            <label class="block text-sm font-medium">Ollama Vision Model</label>
            <input
              type="text"
              name="config[ollama_vision_model]"
              value={@settings.ollama_vision_model || ""}
              placeholder="llava"
              class="w-full border border-input rounded px-3 py-2 text-sm bg-background font-mono"
            />
            <p class="text-xs text-muted-foreground">
              Model used for image analysis (default: llava)
            </p>
          </div>

          <div class="space-y-1">
            <label class="block text-sm font-medium">Default GitHub Repo</label>
            <input
              type="text"
              name="config[default_repo]"
              value={@settings.default_repo || ""}
              placeholder="owner/repo"
              class="w-full border border-input rounded px-3 py-2 text-sm bg-background font-mono"
            />
            <p class="text-xs text-muted-foreground">
              Fallback repo for GitHub tools when no repo is specified
            </p>
          </div>

          <div class="flex items-center gap-3">
            <.button type="submit" size="sm">Save Config</.button>
            <%= if @saved == :config do %>
              <span class="text-xs t-green">Saved.</span>
            <% end %>
          </div>
        </form>
      </.panel>

      <%!-- Banner / Lobe Selection --%>
      <.panel title="Lobe">
        <div class="space-y-3">
          <p class="text-sm text-muted-foreground">
            Select a lobe to filter the pathway browser to a domain focus.
            Affects which cluster pathways are surfaced in Town Square.
          </p>

          <div class="flex flex-wrap gap-2">
            <button
              type="button"
              phx-click="set_banner"
              phx-value-banner=""
              class={"px-3 py-1.5 rounded text-sm border transition-colors " <> if(is_nil(@banner), do: "border-primary bg-primary text-primary-foreground", else: "border-input bg-background hover:bg-muted")}
            >
              All
            </button>
            <%= for lobe <- @banners do %>
              <button
                type="button"
                phx-click="set_banner"
                phx-value-banner={lobe}
                class={"px-3 py-1.5 rounded text-sm border capitalize transition-colors " <> if(@banner == lobe, do: "border-primary bg-primary text-primary-foreground", else: "border-input bg-background hover:bg-muted")}
              >
                {lobe}
              </button>
            <% end %>
          </div>

          <div class="flex items-center gap-2 text-sm">
            <span class="text-muted-foreground">Active lobe:</span>
            <%= if @banner do %>
              <.status color="cyan" label={@banner} />
            <% else %>
              <.status color="amber" label="none (all pathways visible)" />
            <% end %>
            <%= if @saved == :banner do %>
              <span class="text-xs t-green ml-2">Saved.</span>
            <% end %>
          </div>
        </div>
      </.panel>
    </div>
    """
  end
end

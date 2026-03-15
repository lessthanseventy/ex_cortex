defmodule ExCortexWeb.SettingsLive do
  @moduledoc false
  use ExCortexWeb, :live_view

  alias ExCortex.Settings

  @sections [
    obsidian: [
      {:obsidian_vault, "Vault name", "text", "e.g. notes"},
      {:obsidian_vault_path, "Vault path", "text", "Absolute path to vault folder for file sync"},
      {:obsidian_sync_enabled, "Sync enabled", "checkbox", "Auto-sync engrams and signal cards to Obsidian"}
    ],
    email: [
      {:notmuch_db_path, "Notmuch config path", "text",
       "Path to .notmuch-config (leave blank for default ~/.notmuch-config)"},
      {:msmtp_account, "msmtp account", "text", "Account name from ~/.msmtprc (leave blank for default)"}
    ],
    github: [
      {:default_repo, "Default repo", "text", "owner/repo used when no repo is specified"}
    ],
    vision: [
      {:vision_provider, "Vision provider", "select", "ollama or claude"},
      {:ollama_vision_model, "Ollama vision model", "text", "e.g. llava (default)"}
    ],
    media: [
      {:media_dir, "Media directory", "text", "Where downloaded media is stored (default /tmp/ex_cortex/media)"},
      {:frame_mode, "Frame extraction mode", "select", "keyframes or interval"}
    ],
    web_search: [
      {:ddgr_num_results, "Default result count", "text", "Number of results per search (default 10)"}
    ],
    nextcloud: [
      {:nextcloud_url, "Nextcloud URL", "text", "e.g. http://localhost:8080"},
      {:nextcloud_user, "Username", "text", "Nextcloud login username"},
      {:nextcloud_password, "Password", "text", "Nextcloud login password"}
    ]
  ]

  @impl true
  def mount(_params, _session, socket) do
    settings = load_all_settings()
    {:ok, assign(socket, settings: settings, saved: nil)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Settings")}
  end

  @impl true
  def handle_event("save_section", %{"section" => section_str} = params, socket) do
    section = String.to_existing_atom(section_str)
    form_data = Map.get(params, "settings", %{})
    keys = Enum.map(@sections[section], fn {k, _, _, _} -> k end)
    Enum.each(keys, fn key -> save_setting(key, Map.get(form_data, Atom.to_string(key))) end)
    {:noreply, assign(socket, settings: load_all_settings(), saved: section)}
  end

  defp save_setting(:obsidian_sync_enabled, value) do
    Settings.put(:obsidian_sync_enabled, value == "true" || value == true)
  end

  defp save_setting(key, value) when is_binary(value) and value != "" do
    Settings.put(key, value)
  end

  defp save_setting(_key, _value), do: :ok

  defp load_all_settings do
    all = Settings.get_all()

    @sections
    |> Enum.flat_map(fn {_section, fields} ->
      Enum.map(fields, fn {key, _, _, _} -> {key, Map.get(all, Atom.to_string(key))} end)
    end)
    |> Map.new()
  end

  defp sections, do: @sections

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :sections, sections())

    ~H"""
    <div class="max-w-2xl mx-auto p-6 space-y-8">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Settings</h1>
        <p class="text-muted-foreground mt-1.5">
          Configure tool integrations and external service connections.
        </p>
      </div>

      <%= for {section, fields} <- @sections do %>
        <div class="border rounded-lg p-4 space-y-4">
          <h2 class="text-lg font-semibold capitalize">
            {section |> to_string() |> String.replace("_", " ")}
          </h2>

          <form phx-submit="save_section">
            <input type="hidden" name="section" value={section} />

            <%= for {key, label, type, hint} <- fields do %>
              <div class="space-y-1 mb-3">
                <label class="block text-sm font-medium">{label}</label>
                <%= if type == "checkbox" do %>
                  <input
                    type="checkbox"
                    name={"settings[#{key}]"}
                    value="true"
                    checked={@settings[key] == true}
                    class="h-4 w-4"
                  />
                <% else %>
                  <input
                    type="text"
                    name={"settings[#{key}]"}
                    value={@settings[key] || ""}
                    placeholder={hint}
                    class="w-full border rounded px-3 py-2 text-sm"
                  />
                <% end %>
                <p class="text-xs text-gray-500">{hint}</p>
              </div>
            <% end %>

            <button
              type="submit"
              class="px-4 py-2 bg-blue-600 text-white rounded text-sm hover:bg-blue-700"
            >
              Save {section |> to_string() |> String.replace("_", " ") |> String.capitalize()}
            </button>

            <%= if @saved == section do %>
              <span class="ml-2 text-green-600 text-sm">Saved!</span>
            <% end %>
          </form>
        </div>
      <% end %>
    </div>
    """
  end
end

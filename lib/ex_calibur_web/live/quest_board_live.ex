defmodule ExCaliburWeb.QuestBoardLive do
  @moduledoc false
  use ExCaliburWeb, :live_view

  import SaladUI.Badge

  alias ExCalibur.Board
  alias ExCalibur.Quests

  @categories [
    triage: "Triage",
    reporting: "Reporting",
    generation: "Generation",
    review: "Review",
    onboarding: "Onboarding"
  ]

  @impl true
  def mount(_params, _session, socket) do
    templates = Board.all()
    templates_with_status = Enum.map(templates, &with_status/1)

    {:ok,
     assign(socket,
       page_title: "Quest Board",
       templates: templates_with_status,
       active_category: nil,
       show_unavailable: false,
       installing: nil,
       installed: MapSet.new()
     )}
  end

  @impl true
  def handle_event("filter_category", %{"category" => cat}, socket) do
    cat_atom = if cat == "", do: nil, else: String.to_existing_atom(cat)
    {:noreply, assign(socket, active_category: cat_atom)}
  end

  @impl true
  def handle_event("toggle_unavailable", _params, socket) do
    {:noreply, assign(socket, show_unavailable: !socket.assigns.show_unavailable)}
  end

  @impl true
  def handle_event("install_template", %{"id" => id}, socket) do
    case Board.get(id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Template not found")}

      template ->
        case Board.install(template) do
          {:ok, _campaign} ->
            installed = MapSet.put(socket.assigns.installed, id)

            {:noreply,
             socket
             |> assign(installed: installed, installing: nil)
             |> put_flash(:info, "\"#{template.name}\" installed! Find it in Quests.")}

          {:error, reason} ->
            {:noreply, put_flash(socket, :error, "Install failed: #{inspect(reason)}")}
        end
    end
  end

  @impl true
  def handle_event("confirm_install", %{"id" => id}, socket) do
    {:noreply, assign(socket, installing: id)}
  end

  @impl true
  def handle_event("cancel_install", _params, socket) do
    {:noreply, assign(socket, installing: nil)}
  end

  defp with_status(template) do
    requirements = Board.check_requirements(template)
    readiness = Board.readiness(template)
    %{template: template, requirements: requirements, readiness: readiness}
  end

  defp visible_templates(templates, active_category, show_unavailable) do
    templates
    |> Enum.filter(fn %{template: t, readiness: r} ->
      category_match = is_nil(active_category) || t.category == active_category
      availability_match = show_unavailable || r != :unavailable
      category_match && availability_match
    end)
  end

  defp category_label(cat), do: @categories[cat] || to_string(cat)

  defp readiness_badge(:ready), do: {"Ready", "default"}
  defp readiness_badge(:almost), do: {"Almost", "secondary"}
  defp readiness_badge(:unavailable), do: {"Missing", "outline"}

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-8">
      <div>
        <h1 class="text-3xl font-bold tracking-tight">Quest Board</h1>
        <p class="text-muted-foreground mt-1.5">
          Pre-configured campaign templates. Install one to add it to your existing guild's quests.
        </p>
      </div>

      <%# Category filter + unavailable toggle %>
      <div class="flex flex-wrap items-center gap-2">
        <button
          phx-click="filter_category"
          phx-value-category=""
          class={[
            "px-3 py-1.5 text-sm rounded-md transition-colors",
            is_nil(@active_category)
              && "bg-accent text-foreground font-medium"
              || "text-muted-foreground hover:bg-accent hover:text-foreground"
          ]}
        >
          All
        </button>
        <%= for {cat, label} <- [triage: "Triage", reporting: "Reporting", generation: "Generation", review: "Review", onboarding: "Onboarding"] do %>
          <button
            phx-click="filter_category"
            phx-value-category={cat}
            class={[
              "px-3 py-1.5 text-sm rounded-md transition-colors",
              @active_category == cat
                && "bg-accent text-foreground font-medium"
                || "text-muted-foreground hover:bg-accent hover:text-foreground"
            ]}
          >
            {label}
          </button>
        <% end %>

        <div class="ml-auto flex items-center gap-2 text-sm text-muted-foreground">
          <button
            phx-click="toggle_unavailable"
            class="hover:text-foreground transition-colors"
          >
            {if @show_unavailable, do: "Hide unavailable", else: "Show all"}
          </button>
        </div>
      </div>

      <%# Template list %>
      <div class="space-y-3">
        <%= for %{template: t, requirements: reqs, readiness: r} <- visible_templates(@templates, @active_category, @show_unavailable) do %>
          <div class={[
            "flex flex-col gap-4 rounded-lg border p-5 sm:flex-row sm:items-start sm:justify-between",
            MapSet.member?(@installed, t.id) && "border-primary bg-accent/50",
            r == :unavailable && "opacity-60"
          ]}>
            <div class="space-y-2 flex-1 min-w-0">
              <div class="flex items-center gap-2 flex-wrap">
                <span class="font-semibold">{t.name}</span>
                <.badge variant="outline" class="text-xs capitalize">{category_label(t.category)}</.badge>
                <%= if MapSet.member?(@installed, t.id) do %>
                  <.badge variant="default">Installed</.badge>
                <% else %>
                  <% {label, variant} = readiness_badge(r) %>
                  <.badge variant={variant}>{label}</.badge>
                <% end %>
              </div>

              <p class="text-sm text-muted-foreground">{t.description}</p>

              <%= if t.suggested_team && t.suggested_team != "" do %>
                <p class="text-xs text-muted-foreground italic">
                  Team: {t.suggested_team}
                </p>
              <% end %>

              <%= if length(reqs) > 0 do %>
                <div class="flex flex-wrap gap-1.5 mt-1">
                  <%= for {met, label} <- reqs do %>
                    <.badge variant={if met, do: "secondary", else: "outline"} class="text-xs gap-1">
                      {if met, do: "✓", else: "○"} {label}
                    </.badge>
                  <% end %>
                </div>
              <% end %>
            </div>

            <div class="ml-4 shrink-0 self-center">
              <%= if MapSet.member?(@installed, t.id) do %>
                <.button variant="outline" size="sm" disabled>
                  Installed
                </.button>
              <% else %>
                <%= if @installing == t.id do %>
                  <div class="flex gap-2">
                    <.button
                      variant="destructive"
                      size="sm"
                      phx-click="install_template"
                      phx-value-id={t.id}
                    >
                      Confirm
                    </.button>
                    <.button variant="outline" size="sm" phx-click="cancel_install">
                      Cancel
                    </.button>
                  </div>
                <% else %>
                  <.button
                    variant={if r == :ready, do: "default", else: "outline"}
                    size="sm"
                    phx-click="confirm_install"
                    phx-value-id={t.id}
                    disabled={r == :unavailable}
                  >
                    Install
                  </.button>
                <% end %>
              <% end %>
            </div>
          </div>
        <% end %>

        <%= if visible_templates(@templates, @active_category, @show_unavailable) == [] do %>
          <div class="text-center py-12 text-muted-foreground">
            <p class="text-sm">No templates available in this category.</p>
            <button phx-click="toggle_unavailable" class="text-sm underline mt-1">
              Show all templates
            </button>
          </div>
        <% end %>
      </div>

      <div class="text-xs text-muted-foreground border-t pt-4">
        Installing a template adds new quests and a campaign to your existing guild. It does not replace current members or quests.
        <a href="/quests" class="underline ml-1">View Quests →</a>
      </div>
    </div>
    """
  end
end

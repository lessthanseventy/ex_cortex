defmodule ExCellenceServerWeb.RolesLive do
  @moduledoc false
  use ExCellenceServerWeb, :live_view

  import ExCellenceUI.Components.RoleForm
  import SaladUI.Badge
  import SaladUI.Card

  alias Excellence.Schemas.ResourceDefinition

  @impl true
  def mount(_params, _session, socket) do
    roles = list_roles()
    {:ok, assign(socket, roles: roles, editing: nil, role_form: nil)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: "Roles", editing: nil)
  end

  defp apply_action(socket, :new, _params) do
    assign(socket,
      page_title: "New Role",
      editing: :new,
      role_form: %{name: "", system_prompt: "", perspectives: [], parse_strategy: "default"}
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case get_role(id) do
      nil ->
        push_navigate(socket, to: "/roles")

      role ->
        assign(socket,
          page_title: "Edit Role",
          editing: role.id,
          role_form: %{
            name: role.name,
            system_prompt: role.config["system_prompt"] || "",
            perspectives: role.config["perspectives"] || [],
            parse_strategy: role.config["parse_strategy"] || "default"
          }
        )
    end
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case ExCellenceServer.Repo.get(ResourceDefinition, id) do
      nil ->
        {:noreply, socket}

      resource ->
        ExCellenceServer.Repo.delete(resource)
        {:noreply, assign(socket, roles: list_roles())}
    end
  end

  @impl true
  def handle_event("save_role", %{"role" => role_params}, socket) do
    attrs = %{
      type: "role",
      name: role_params["name"],
      status: "draft",
      source: "db",
      config: %{
        "system_prompt" => role_params["system_prompt"],
        "perspectives" => parse_perspectives(role_params),
        "parse_strategy" => role_params["parse_strategy"] || "default"
      }
    }

    result =
      case socket.assigns.editing do
        :new ->
          %ResourceDefinition{}
          |> ResourceDefinition.changeset(attrs)
          |> ExCellenceServer.Repo.insert()

        id ->
          ResourceDefinition
          |> ExCellenceServer.Repo.get!(id)
          |> ResourceDefinition.changeset(attrs)
          |> ExCellenceServer.Repo.update()
      end

    case result do
      {:ok, _} ->
        {:noreply, socket |> push_navigate(to: "/roles") |> put_flash(:info, "Role saved")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Failed to save role")}
    end
  end

  @impl true
  def handle_event("update_status", %{"id" => id, "status" => status}, socket) do
    case ExCellenceServer.Repo.get(ResourceDefinition, id) do
      nil ->
        {:noreply, socket}

      resource ->
        resource |> ResourceDefinition.changeset(%{status: status}) |> ExCellenceServer.Repo.update()
        {:noreply, assign(socket, roles: list_roles())}
    end
  end

  @impl true
  def handle_event("add_perspective", _params, socket) do
    perspectives = (socket.assigns.role_form[:perspectives] || []) ++ [%{name: "", model: "", strategy: "cod"}]
    {:noreply, assign(socket, role_form: Map.put(socket.assigns.role_form, :perspectives, perspectives))}
  end

  @impl true
  def handle_event("remove_perspective", %{"index" => index}, socket) do
    idx = String.to_integer(index)
    perspectives = List.delete_at(socket.assigns.role_form[:perspectives] || [], idx)
    {:noreply, assign(socket, role_form: Map.put(socket.assigns.role_form, :perspectives, perspectives))}
  end

  defp list_roles do
    import Ecto.Query

    ExCellenceServer.Repo.all(from(r in ResourceDefinition, where: r.type == "role", order_by: [desc: r.inserted_at]))
  end

  defp get_role(id) do
    import Ecto.Query

    ExCellenceServer.Repo.one(from(r in ResourceDefinition, where: r.type == "role" and r.id == ^id))
  end

  defp parse_perspectives(%{"perspectives" => perspectives}) when is_map(perspectives) do
    perspectives
    |> Enum.sort_by(fn {k, _v} -> k end)
    |> Enum.map(fn {_k, v} -> v end)
  end

  defp parse_perspectives(_), do: []

  @impl true
  def render(assigns) do
    ~H"""
    <div class="space-y-6">
      <div class="flex items-center justify-between">
        <h1 class="text-2xl font-bold">Roles</h1>
        <.link navigate="/roles/new">
          <.button>New Role</.button>
        </.link>
      </div>

      <%= if @editing do %>
        <.role_form
          role={@role_form}
          on_save="save_role"
          on_cancel={JS.navigate("/roles")}
        />
      <% else %>
        <div class="grid gap-4">
          <%= for role <- @roles do %>
            <.card>
              <.card_header>
                <div class="flex items-center justify-between">
                  <.card_title>{role.name}</.card_title>
                  <.badge variant={status_variant(role.status)}>{role.status}</.badge>
                </div>
              </.card_header>
              <.card_content>
                <div class="flex items-center gap-2">
                  <%= for p <- (role.config["perspectives"] || []) do %>
                    <.badge variant="outline">
                      {p["name"] || p[:name]} · {p["model"] || p[:model]}
                    </.badge>
                  <% end %>
                </div>
              </.card_content>
              <.card_footer>
                <div class="flex gap-2">
                  <.link navigate={"/roles/#{role.id}/edit"}>
                    <.button variant="outline" size="sm">Edit</.button>
                  </.link>
                  <%= if role.status == "draft" do %>
                    <.button
                      variant="outline"
                      size="sm"
                      phx-click="update_status"
                      phx-value-id={role.id}
                      phx-value-status="active"
                    >
                      Activate
                    </.button>
                  <% end %>
                  <%= if role.status == "active" do %>
                    <.button
                      variant="outline"
                      size="sm"
                      phx-click="update_status"
                      phx-value-id={role.id}
                      phx-value-status="shadow"
                    >
                      Shadow
                    </.button>
                    <.button
                      variant="outline"
                      size="sm"
                      phx-click="update_status"
                      phx-value-id={role.id}
                      phx-value-status="paused"
                    >
                      Pause
                    </.button>
                  <% end %>
                  <.button
                    variant="destructive"
                    size="sm"
                    phx-click="delete"
                    phx-value-id={role.id}
                    data-confirm="Are you sure?"
                  >
                    Delete
                  </.button>
                </div>
              </.card_footer>
            </.card>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  defp status_variant("active"), do: "default"
  defp status_variant("draft"), do: "secondary"
  defp status_variant("shadow"), do: "outline"
  defp status_variant("paused"), do: "destructive"
  defp status_variant("archived"), do: "secondary"
  defp status_variant(_), do: "secondary"
end

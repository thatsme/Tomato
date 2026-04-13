defmodule TomatoWeb.GraphLive.ModalComponents do
  @moduledoc """
  Modal function components for the Tomato graph editor.

  Public function components:

    * `template_picker/1` — browse and add nodes from the template library
    * `oodn_editor/1`     — edit the OODN key/value registry
    * `content_editor/1`  — edit the Nix fragment content of a leaf node
    * `generated_output/1` — show generated Nix output with deploy controls
    * `graph_manager/1`   — list, load, create and delete graph files

  All components are pure — they read from explicit attrs and emit
  `phx-click` / `phx-submit` events that the LiveView handles.
  """

  use Phoenix.Component

  alias Phoenix.LiveView.JS

  # --- Template Picker ---

  def template_picker(assigns) do
    categories = Tomato.TemplateLibrary.by_category()
    assigns = assign(assigns, :categories, categories)

    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_template_picker" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[600px] max-h-[80vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300 shrink-0">
            <div>
              <h2 class="font-semibold">Add Node from Template</h2>
              <p class="text-xs text-base-content/50">Pick a predefined NixOS configuration</p>
            </div>
            <button class="btn btn-sm btn-ghost" phx-click="close_template_picker">X</button>
          </div>

          <div class="flex-1 min-h-0 overflow-y-auto p-4 space-y-4">
            <div :for={{category, templates} <- @categories}>
              <h3 class="text-xs font-semibold text-base-content/50 uppercase mb-2">{category}</h3>
              <div class="grid grid-cols-2 gap-2">
                <button
                  :for={t <- templates}
                  class={[
                    "flex flex-col items-start p-3 rounded-lg border transition-colors cursor-pointer text-left",
                    Map.get(t, :type) == :gateway &&
                      "border-secondary/40 hover:border-secondary hover:bg-secondary/5",
                    Map.get(t, :type) != :gateway &&
                      "border-base-300 hover:border-primary hover:bg-primary/5"
                  ]}
                  phx-click="add_from_template"
                  phx-value-template-id={t.id}
                >
                  <div class="flex items-center gap-2">
                    <span :if={Map.get(t, :type) == :gateway} class="badge badge-xs badge-secondary">
                      stack
                    </span>
                    <span class="font-medium text-sm">{t.name}</span>
                  </div>
                  <span class="text-xs text-base-content/50 mt-0.5">{t.description}</span>
                  <div :if={Map.get(t, :children)} class="text-xs text-base-content/40 mt-1">
                    {length(Map.get(t, :children, []))} nodes inside
                  </div>
                  <div :if={t.oodn_keys != []} class="flex gap-1 mt-1.5 flex-wrap">
                    <span
                      :for={key <- t.oodn_keys}
                      class="badge badge-xs badge-warning font-mono"
                    >
                      {"${" <> key <> "}"}
                    </span>
                  </div>
                </button>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- OODN Editor ---

  attr :oodn_registry, :map, required: true

  def oodn_editor(assigns) do
    entries = assigns.oodn_registry |> Map.values() |> Enum.sort_by(& &1.key)
    assigns = assign(assigns, :entries, entries)

    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_oodn_editor" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[500px] max-h-[80vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <div>
              <h2 class="font-semibold">OODN Config</h2>
              <p class="text-xs text-base-content/50">
                Global variables — use ${"{key}"} in leaf nodes
              </p>
            </div>
            <button class="btn btn-sm btn-ghost" phx-click="close_oodn_editor">X</button>
          </div>

          <div class="flex-1 overflow-y-auto p-4 space-y-2">
            <div
              :for={entry <- @entries}
              class="flex items-center gap-2"
            >
              <span class="font-mono text-sm font-semibold w-32 shrink-0 truncate" title={entry.key}>
                {entry.key}
              </span>
              <form phx-submit="update_oodn" phx-value-oodn-id={entry.id} class="flex-1 flex gap-1">
                <input
                  type="text"
                  name="value"
                  value={entry.value}
                  class="input input-sm input-bordered flex-1 font-mono"
                />
                <button type="submit" class="btn btn-sm btn-ghost">Save</button>
              </form>
              <button
                class="btn btn-sm btn-ghost text-error"
                phx-click="remove_oodn"
                phx-value-oodn-id={entry.id}
              >
                x
              </button>
            </div>
          </div>

          <div class="p-4 border-t border-base-300">
            <form phx-submit="add_oodn" class="flex gap-2">
              <input
                type="text"
                name="key"
                placeholder="key"
                class="input input-sm input-bordered w-32 font-mono"
                required
              />
              <input
                type="text"
                name="value"
                placeholder="value"
                class="input input-sm input-bordered flex-1 font-mono"
                required
              />
              <button type="submit" class="btn btn-sm btn-warning">Add</button>
            </form>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Content Editor ---

  attr :node, :map, required: true

  def content_editor(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_editor" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[700px] max-h-[80vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <div>
              <h2 class="font-semibold">{@node.name}</h2>
              <p class="text-xs text-base-content/50">Nix configuration fragment</p>
            </div>
            <button class="btn btn-sm btn-ghost" phx-click="close_editor">X</button>
          </div>
          <form
            phx-submit="save_content"
            phx-value-node-id={@node.id}
            class="flex flex-col flex-1 min-h-0"
          >
            <div class="flex-1 p-4 min-h-0">
              <textarea
                name="content"
                class="textarea textarea-bordered w-full h-full min-h-[300px] font-mono text-sm"
                placeholder={"# Nix config for #{@node.name}\n# e.g.:\n# services.openssh.enable = true;\n# services.openssh.settings.PermitRootLogin = \"no\";"}
                phx-debounce="500"
              >{@node.content || ""}</textarea>
            </div>
            <div class="flex justify-end gap-2 p-4 border-t border-base-300">
              <button type="button" class="btn btn-sm btn-ghost" phx-click="close_editor">
                Cancel
              </button>
              <button type="submit" class="btn btn-sm btn-primary">Save</button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  # --- Generated Output ---

  defp validation_panel(%{validation: :ok} = assigns) do
    ~H"""
    <div class="rounded-lg p-3 text-sm bg-success/10 text-success flex items-center gap-2">
      <span class="font-semibold">Nix syntax OK</span>
      <span class="text-xs opacity-70">all leaf fragments parse cleanly</span>
    </div>
    """
  end

  defp validation_panel(%{validation: :unavailable} = assigns) do
    ~H"""
    <div class="rounded-lg p-3 text-sm bg-warning/10 text-warning">
      <div class="font-semibold">Nix CLI not found</div>
      <div class="text-xs opacity-70">
        Install <code>nix-instantiate</code> to enable local syntax validation.
      </div>
    </div>
    """
  end

  defp validation_panel(%{validation: {:error, _errs}} = assigns) do
    ~H"""
    <div class="rounded-lg bg-error/10 text-error">
      <div class="p-3 border-b border-error/20">
        <div class="font-semibold">
          Nix syntax errors ({length(elem(@validation, 1))})
        </div>
        <div class="text-xs opacity-70">
          Local check only — Deploy/Switch remain enabled (target Nix may differ).
        </div>
      </div>
      <ul class="divide-y divide-error/20">
        <li
          :for={err <- elem(@validation, 1)}
          class="p-3 cursor-pointer hover:bg-error/5"
          phx-click={
            JS.push("select_node", value: %{"node-id" => err.node_id})
            |> JS.push("close_generated")
          }
        >
          <div class="font-mono text-xs font-semibold">{err.node_name}</div>
          <pre class="text-xs whitespace-pre-wrap mt-1 opacity-80">{err.reason}</pre>
        </li>
      </ul>
    </div>
    """
  end

  defp validation_panel(%{validation: :disabled} = assigns) do
    ~H"""
    """
  end

  attr :output, :string, required: true
  attr :path, :string, default: nil
  attr :validation, :any, default: :disabled
  attr :deploy_status, :string, default: nil
  attr :deploy_output, :string, default: nil

  def generated_output(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_generated" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[800px] max-h-[85vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300 shrink-0">
            <div>
              <h2 class="font-semibold">Generated Output</h2>
              <p :if={@path} class="text-xs text-success">Saved to: {@path}</p>
            </div>
            <button class="btn btn-sm btn-ghost" phx-click="close_generated">X</button>
          </div>

          <%!-- Scrollable content area --%>
          <div class="flex-1 min-h-0 overflow-y-auto p-4 space-y-4">
            <.validation_panel validation={@validation} />
            <pre class="bg-base-200 rounded-lg p-4 text-sm font-mono whitespace-pre overflow-x-auto"><code>{@output}</code></pre>

            <%!-- Deploy status inside scroll area --%>
            <div
              :if={@deploy_status}
              class={[
                "rounded-lg p-3 text-sm font-mono whitespace-pre-wrap",
                @deploy_status == "running" && "bg-info/10 text-info",
                @deploy_status == "success" && "bg-success/10 text-success",
                @deploy_status == "error" && "bg-error/10 text-error"
              ]}
            >
              <div class="font-semibold mb-1">
                <span :if={@deploy_status == "running"}>Deploying...</span>
                <span :if={@deploy_status == "success"}>Deploy successful</span>
                <span :if={@deploy_status == "error"}>Deploy failed</span>
              </div>
              <div :if={@deploy_output != ""}>{@deploy_output}</div>
            </div>
          </div>

          <%!-- Fixed footer --%>
          <div class="flex flex-wrap justify-end gap-2 p-4 border-t border-base-300 shrink-0">
            <button type="button" class="btn btn-sm btn-ghost" phx-click="close_generated">
              Close
            </button>
            <button
              type="button"
              class={[
                "btn btn-sm btn-outline btn-error",
                @deploy_status == "running" && "btn-disabled"
              ]}
              phx-click="rollback"
              disabled={@deploy_status == "running"}
              data-confirm="Rollback to previous generation?"
              title="nixos-rebuild switch --rollback"
            >
              Rollback
            </button>
            <button
              type="button"
              class={[
                "btn btn-sm btn-outline btn-info",
                @deploy_status == "running" && "btn-disabled"
              ]}
              phx-click="show_diff"
              disabled={@deploy_status == "running"}
              title="Show diff against current config on machine"
            >
              Diff
            </button>
            <button
              type="button"
              class={[
                "btn btn-sm btn-outline btn-secondary",
                @deploy_status == "running" && "btn-disabled"
              ]}
              phx-click="reconfigure"
              phx-value-mode="dry_activate"
              disabled={@deploy_status == "running"}
              title="nixos-rebuild dry-activate — show what would change"
            >
              Dry Run
            </button>
            <button
              type="button"
              class={[
                "btn btn-sm btn-secondary",
                @deploy_status == "running" && "btn-disabled loading"
              ]}
              phx-click="reconfigure"
              phx-value-mode="test"
              disabled={@deploy_status == "running"}
              title="nixos-rebuild test — apply without boot entry"
            >
              Test
            </button>
            <button
              type="button"
              class={["btn btn-sm btn-warning", @deploy_status == "running" && "btn-disabled loading"]}
              phx-click="reconfigure"
              phx-value-mode="switch"
              disabled={@deploy_status == "running"}
              title="nixos-rebuild switch — apply and add to boot menu"
            >
              Switch
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # --- Graph Manager ---

  attr :graph_list, :list, required: true
  attr :current_file, :string, default: nil

  def graph_manager(assigns) do
    ~H"""
    <div class="fixed inset-0 z-40 overflow-y-auto">
      <div class="fixed inset-0 bg-black/50" phx-click="close_graph_manager" />
      <div class="flex min-h-full items-center justify-center p-4">
        <div class="relative bg-base-100 rounded-lg shadow-2xl w-[500px] max-h-[80vh] flex flex-col">
          <div class="flex items-center justify-between p-4 border-b border-base-300">
            <h2 class="font-semibold">Graph Manager</h2>
            <button class="btn btn-sm btn-ghost" phx-click="close_graph_manager">X</button>
          </div>

          <%!-- New graph --%>
          <div class="p-4 border-b border-base-300">
            <form phx-submit="new_graph_submit" class="flex gap-2">
              <input
                type="text"
                name="name"
                placeholder="New graph name..."
                class="input input-sm input-bordered flex-1"
                required
              />
              <button type="submit" class="btn btn-sm btn-primary">New</button>
            </form>
          </div>

          <%!-- Save As --%>
          <div class="px-4 py-3 border-b border-base-300">
            <form phx-submit="save_as_submit" class="flex gap-2">
              <input
                type="text"
                name="name"
                placeholder="Save current graph as..."
                class="input input-sm input-bordered flex-1"
                required
              />
              <button type="submit" class="btn btn-sm btn-secondary">Save As</button>
            </form>
          </div>

          <%!-- File list --%>
          <div class="flex-1 overflow-y-auto p-4">
            <h3 class="text-xs font-semibold text-base-content/60 mb-3 uppercase">Saved Graphs</h3>
            <div :if={@graph_list == []} class="text-sm text-base-content/40 text-center py-4">
              No saved graphs yet
            </div>
            <div class="space-y-1">
              <div
                :for={item <- @graph_list}
                class={[
                  "flex items-center gap-3 px-3 py-2 rounded",
                  item.filename == @current_file && "bg-primary/10 border border-primary/20",
                  item.filename != @current_file && "hover:bg-base-200"
                ]}
              >
                <div class="flex-1 min-w-0">
                  <div class="text-sm font-medium truncate">{item.name}</div>
                  <div class="text-xs text-base-content/40">{item.filename}</div>
                </div>
                <div class="flex gap-1 shrink-0">
                  <button
                    :if={item.filename != @current_file}
                    class="btn btn-xs btn-ghost"
                    phx-click="load_graph_file"
                    phx-value-filename={item.filename}
                  >
                    Load
                  </button>
                  <span :if={item.filename == @current_file} class="badge badge-xs badge-primary">
                    active
                  </span>
                  <button
                    :if={item.filename != @current_file}
                    class="btn btn-xs btn-ghost text-error"
                    phx-click="delete_graph_file"
                    phx-value-filename={item.filename}
                    data-confirm="Delete this graph?"
                  >
                    Del
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end

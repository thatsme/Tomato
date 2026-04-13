defmodule Tomato.Deploy.Diff do
  @moduledoc """
  Line-based unified-style diff between two strings.
  """

  @doc """
  Returns an empty string for identical input, otherwise a summary of
  removed and added lines prefixed with `-` and `+`.
  """
  @spec simple_diff(String.t(), String.t()) :: String.t()
  def simple_diff(old, new) do
    old_lines = String.split(old, "\n")
    new_lines = String.split(new, "\n")

    if old_lines == new_lines do
      ""
    else
      old_set = MapSet.new(old_lines)
      new_set = MapSet.new(new_lines)

      removed = Enum.reject(old_lines, &MapSet.member?(new_set, &1))
      added = Enum.reject(new_lines, &MapSet.member?(old_set, &1))

      removed_str = Enum.map_join(removed, "\n", &("- " <> &1))
      added_str = Enum.map_join(added, "\n", &("+ " <> &1))

      [removed_str, added_str]
      |> Enum.reject(&(&1 == ""))
      |> Enum.join("\n")
    end
  end
end

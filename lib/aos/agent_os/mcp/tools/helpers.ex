defmodule AOS.AgentOS.MCP.Tools.Helpers do
  @moduledoc false

  alias AOS.AgentOS.Config

  def validate_workspace_path(path) do
    root = workspace_root()
    expanded = Path.expand(path, root)

    if inside_workspace?(expanded, root) do
      {:ok, expanded}
    else
      {:error, :path_outside_workspace}
    end
  end

  def inside_workspace?(path, root \\ workspace_root()) do
    expanded_path = Path.expand(path)
    expanded_root = Path.expand(root)

    expanded_path == expanded_root or
      String.starts_with?(expanded_path, expanded_root <> "/")
  end

  def workspace_root do
    Config.workspace_root()
  end

  def maybe_truncate(content, max_len) when byte_size(content) <= max_len, do: content

  def maybe_truncate(content, max_len),
    do: binary_part(content, 0, max_len) <> "\n...<truncated>"

  def render_file_change(path, nil, new_content) do
    """
    File: #{path}
    Status: created

    +++ new
    #{prefix_lines(new_content, "+ ") |> maybe_truncate(6000)}
    """
  end

  def render_file_change(path, previous_content, new_content) do
    diff =
      previous_content
      |> String.split("\n", trim: false)
      |> List.myers_difference(String.split(new_content, "\n", trim: false))
      |> Enum.flat_map(fn
        {:eq, lines} -> Enum.map(lines, &("  " <> &1))
        {:ins, lines} -> Enum.map(lines, &("+ " <> &1))
        {:del, lines} -> Enum.map(lines, &("- " <> &1))
      end)
      |> Enum.join("\n")

    """
    File: #{path}
    Status: updated

    --- before
    +++ after
    #{maybe_truncate(diff, 6000)}
    """
  end

  def prefix_lines(content, prefix) do
    content
    |> String.split("\n", trim: false)
    |> Enum.map_join("\n", &(prefix <> &1))
  end
end

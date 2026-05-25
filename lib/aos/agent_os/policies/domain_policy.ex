defmodule AOS.AgentOS.Policies.DomainPolicy do
  @moduledoc """
  Enforces domain-specific rules (e.g., mandatory evaluation for coding).
  Supports both atom and string node IDs in history.
  """
  @behaviour AOS.AgentOS.Core.Policy
  require Logger
  alias AOS.AgentOS.Core.Nodes.LLMEvaluator
  alias AOS.AgentOS.Roles.Reporter

  @impl true
  def check(context, next_node_id) do
    domain = context |> Map.get(:domain, :general) |> normalize_domain()
    history = Map.get(context, :execution_history, [])
    graph_nodes = Map.get(context, :graph_nodes, %{})
    next_module = Map.get(graph_nodes, next_node_id)

    if domain == "coding" and reporter_node?(next_node_id, next_module) do
      has_evaluated =
        Enum.any?(history, fn step ->
          node_id = step[:node_id] || step["node_id"]
          evaluator_node?(node_id, Map.get(graph_nodes, node_id))
        end)

      if has_evaluated do
        {:ok, context}
      else
        Logger.error("[DomainPolicy] Coding task must be evaluated before reporting results!")
        {:error, :evaluation_required}
      end
    else
      {:ok, context}
    end
  end

  defp normalize_domain(domain), do: domain |> to_string() |> String.downcase()

  defp reporter_node?(_node_id, Reporter), do: true
  defp reporter_node?(node_id, _module), do: to_string(node_id) == "reporter"

  defp evaluator_node?(_node_id, LLMEvaluator), do: true

  defp evaluator_node?(node_id, _module) do
    to_string(node_id) in ["critic", "evaluator", "reviewer", "reviewer_agent"]
  end
end

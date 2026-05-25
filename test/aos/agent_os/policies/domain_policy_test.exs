defmodule AOS.AgentOS.Policies.DomainPolicyTest do
  use ExUnit.Case, async: true

  alias AOS.AgentOS.Core.Nodes.LLMEvaluator
  alias AOS.AgentOS.Policies.DomainPolicy
  alias AOS.AgentOS.Roles.Reporter

  test "blocks coding reports that have not passed through an evaluator module" do
    context = %{
      domain: "coding",
      execution_history: [%{node_id: "n1"}],
      graph_nodes: %{"n1" => AOS.AgentOS.Core.Nodes.LLMWorker, "n2" => Reporter}
    }

    assert {:error, :evaluation_required} = DomainPolicy.check(context, "n2")
  end

  test "allows coding reports after an evaluator module ran" do
    context = %{
      domain: "coding",
      execution_history: [%{node_id: "n1"}],
      graph_nodes: %{"n1" => LLMEvaluator, "n2" => Reporter}
    }

    assert {:ok, ^context} = DomainPolicy.check(context, "n2")
  end

  test "normalizes atom coding domains" do
    context = %{
      domain: :coding,
      execution_history: [],
      graph_nodes: %{"report" => Reporter}
    }

    assert {:error, :evaluation_required} = DomainPolicy.check(context, "report")
  end
end
